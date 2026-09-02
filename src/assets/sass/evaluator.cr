# Evaluator: SCSS AST → flat CSS tree.
#
# Handles variable scoping, selector nesting and `&` resolution,
# conditional at-rule bubbling (@media/@supports inside rules), mixin
# expansion with @content, control flow (@if/@each/@for/@while),
# @function/@return, and @use/@import/@forward module loading.
#
# Values are stored as verbatim strings after substitution and coerced
# into typed values only where expressions demand it: declaration and
# variable values go through the *lenient* expression path (compute when
# the tree contains operators or known functions, otherwise — and on any
# failure — fall back to the legacy verbatim text, keeping plain-CSS
# passthrough byte-identical). Control-flow headers, @return, and
# @use ... with are *strict*: failures surface as located SyntaxErrors.

require "./ast"
require "./environment"
require "./css"
require "./importer"
require "./parser"
require "./value"
require "./expr"
require "./extend"
require "./functions"
require "../../utils/logger"

module Hwaro
  module Assets
    module Sass
      class Evaluator
        include Expr::Host

        MAX_INCLUDE_DEPTH    =     100
        MAX_CALL_DEPTH       =     100
        MAX_WHILE_ITERATIONS = 100_000
        # Total loop-body evaluations across `@for`/`@each`/`@while` in ONE
        # compile. `MAX_WHILE_ITERATIONS` bounds a single `@while` and nothing
        # bounded `@for` at all, so `@for $i from 1 through 100000000` — one
        # mistyped bound — emitted rules until the process ran out of memory,
        # and nesting two capped loops still multiplies. A shared budget is the
        # only form that survives nesting. Six figures of loop bodies is orders
        # of magnitude past any real stylesheet (palettes and grid systems land
        # in the hundreds).
        MAX_LOOP_ITERATIONS = 1_000_000
        # `&` slots per selector beyond which the parent cross-product is
        # not expanded (it grows as parents**slots).
        MAX_PARENT_REF_SLOTS = 4
        # Ceiling on the selectors ONE rule may expand to. `MAX_PARENT_REF_SLOTS`
        # bounds the exponent but not the base, and the base is the enclosing
        # rule's own expansion — so nesting compounds:
        #
        #     .a,.b,…,.j { & & { & & { & & { color: red } } } }
        #
        # is 10 → 10² → 10⁴ → 10⁸ selectors from eight lines of SCSS. The build
        # did not crash, it simply never finished, allocating the whole way.
        # No hand-written rule needs four figures of selectors, so cap it and
        # say so instead of hanging.
        MAX_RULE_SELECTORS = 8192

        # Unwinds a @function body at @return. :nodoc:
        class ReturnSignal < Exception
          getter value : Value

          def initialize(@value)
            super("@return")
          end
        end

        # A `{ ... }` block passed to `@include`; evaluated at `@content`
        # with the caller's variable scope (dart-sass lexical semantics).
        # `params` are the `using ($a, $b: 1)` parameters that
        # `@content(...)` arguments bind to.
        # :nodoc:
        class ContentBlock
          getter nodes : Array(Ast::Node)
          getter env : Environment
          getter outer : ContentBlock?
          getter path : String
          getter params : Array(Ast::Param)

          def initialize(@nodes, @env, @outer, @path, @params = [] of Ast::Param)
          end
        end

        # An at-rule the evaluator is currently writing into, with the sink
        # that CONTAINS it. Needed to reopen the at-rule when later content
        # arrives after something else (a merged nested @media) was emitted
        # beside it, and to find enclosing @media preludes for merging.
        # :nodoc:
        class AtFrame
          property at : Css::AtRule
          getter container : Array(Css::Node)

          def initialize(@at, @container)
          end
        end

        @env : Environment
        @sink : Array(Css::Node)
        @current_rule : Css::Rule?
        @current_rule_sink : Array(Css::Node)?
        @at_frames : Array(AtFrame)
        @current_at : Css::AtRule?
        @parent_selectors : Array(String)?
        # Line-break flags for @parent_selectors (see Css::Rule#breaks);
        # saved/restored wherever @parent_selectors is.
        @parent_breaks : Array(Bool)?
        @content : ContentBlock?
        @in_keyframes : Bool
        @include_depth : Int32
        @loop_iterations : Int64
        @path : String

        def initialize(@importer : Importer, path : String)
          @env = Environment.new
          @sink = [] of Css::Node
          @current_rule = nil
          @current_at = nil
          @parent_selectors = nil
          @parent_breaks = nil
          @content = nil
          @in_keyframes = false
          @include_depth = 0
          @loop_iterations = 0_i64
          @path = path
          # Sink the current rule was emitted into; when it is no longer
          # the sink's last node (a nested rule was emitted after it),
          # later declarations reopen a fresh rule with the same selectors
          # to preserve cascade order (dart-sass behavior).
          @current_rule_sink = nil
          # Enclosing at-rule stack (innermost last) — see AtFrame.
          @at_frames = [] of AtFrame
          @loaded_modules = {} of String => SassModule
          @load_stack = [] of String
          @in_function = false
          @call_depth = 0
          @forward_variables = {} of String => String
          @forward_mixins = {} of String => MixinClosure
          @forward_functions = {} of String => SassFn
          # The importing file's globals while a classic `@import` is being
          # evaluated — dart-sass's "implicit configuration". A `@forward`
          # reached through the import configures its module's `!default`
          # variables from it (see `forward_config`); nil outside an import
          # and inside any `@use` (which never inherits it).
          @import_config = nil.as(Hash(String, String)?)
          # @extend requests, applied document-wide as a post-pass —
          # deliberately NOT saved/restored around module loads.
          @extends = [] of Extend::Request
          # Rest-parameter names whose `meta.keywords($args)` store was
          # read (or forwarded via `$args...`) during the current mixin /
          # function / @content body. Unused extra keywords error.
          @keywords_accessed = Set(String).new
        end

        # Registers the entry file's canonical path so a self-import cycle
        # is caught at the first hop.
        def seed_load_stack(canonical : String) : Nil
          @load_stack << canonical
        end

        def evaluate(sheet : Ast::Stylesheet) : Array(Css::Node)
          eval_nodes(sheet.children)
          apply_extends
          Extend.scrub_placeholders(@sink)
          @sink
        end

        private def eval_nodes(nodes : Array(Ast::Node)) : Nil
          nodes.each { |node| eval_node(node) }
        end

        private def eval_node(node : Ast::Node) : Nil
          if @in_function
            case node
            when Ast::VarDeclNode, Ast::IfNode, Ast::EachNode, Ast::ForNode,
                 Ast::WhileNode, Ast::ReturnNode, Ast::MessageNode,
                 Ast::FunctionDefNode
              # allowed in @function bodies
            when Ast::CommentNode
              return # never emits CSS from inside a function
            else
              error_at(node.line, node.column,
                "@function bodies may only contain variable declarations, control flow, and @return")
            end
          end

          case node
          when Ast::VarDeclNode
            @env.assign_var(node.name, resolve_value(node.value), node.default, node.global)
          when Ast::MixinDefNode
            @env.declare_mixin(node.name, MixinClosure.new(node, @env, @path))
          when Ast::FunctionDefNode
            @env.declare_function(node.name, FunctionClosure.new(node, @env, @path))
          when Ast::RuleNode
            # A top-level style rule's output forms a "group" — the
            # serializer puts a blank line after its last root node
            # (dart-sass's isGroupEnd). At-rule statements never mark one,
            # and rules nested in at-rules (@media children) don't either.
            top_level = @current_rule.nil? && @at_frames.empty? &&
                        @parent_selectors.nil? && !@in_keyframes
            eval_rule(node)
            if top_level && (last = @sink.last?)
              last.group_end = true
            end
          when Ast::DeclarationNode
            eval_declaration(node)
          when Ast::NestedPropsNode
            eval_nested_props(node)
          when Ast::IncludeNode
            eval_include(node)
          when Ast::ContentNode
            eval_content(node)
          when Ast::IfNode
            eval_if(node)
          when Ast::EachNode
            eval_each(node)
          when Ast::ForNode
            eval_for(node)
          when Ast::WhileNode
            eval_while(node)
          when Ast::ReturnNode
            error_at(node.line, node.column, "@return may only be used within a @function") unless @in_function
            raise ReturnSignal.new(eval_expr!(node.value))
          when Ast::MessageNode
            eval_message(node)
          when Ast::AtRootNode
            eval_at_root(node)
          when Ast::ExtendNode
            eval_extend(node)
          when Ast::UseNode
            eval_use(node)
          when Ast::ImportNode
            eval_import(node)
          when Ast::ForwardNode
            eval_forward(node)
          when Ast::RawAtRuleNode
            eval_at_rule(node)
          when Ast::CommentNode
            emit_comment(comment_text(node))
          end
        end

        # Comments are the most lenient context of all: a `#{...}` that
        # fails to resolve (undefined variable in commented-out Sass, a
        # `#{...}` that was never meant as interpolation) keeps the
        # comment byte-identical instead of failing the build.
        private def comment_text(node : Ast::CommentNode) : String
          if template = node.template
            begin
              return resolve_template(template, allow_vars: true)
            rescue SyntaxError
              # fall through to the verbatim text
            end
          end
          node.text
        end

        # ---------------------------------------------------------------
        # Rules & declarations
        # ---------------------------------------------------------------

        private def eval_rule(node : Ast::RuleNode) : Nil
          text = resolve_template(node.selector, allow_vars: false)
          parts, part_breaks = selector_parts(text)
          error_at(node.line, node.column, "expected selector") if parts.empty?

          if @in_keyframes
            # dart-sass always joins keyframe selector lists onto one
            # line, author line breaks notwithstanding (`0%,\n100%` prints
            # `0%, 100%`).
            selectors, breaks = parts, [] of Bool
          else
            selectors, breaks = combine_selectors(parts, part_breaks, node)
          end
          rule = Css::Rule.new(selectors, breaks)
          emit(rule)

          saved_rule = @current_rule
          saved_rule_sink = @current_rule_sink
          saved_parents = @parent_selectors
          saved_breaks = @parent_breaks
          saved_env = @env
          @current_rule = rule
          @current_rule_sink = @sink
          @parent_selectors = selectors
          @parent_breaks = breaks
          @env = Environment.new(saved_env) # each block is a variable scope
          eval_nodes(node.children)
          @current_rule = saved_rule
          @current_rule_sink = saved_rule_sink
          @parent_selectors = saved_parents
          @parent_breaks = saved_breaks
          @env = saved_env
        end

        # Splits a selector list on top-level commas, remembering which
        # selectors had a line break in the whitespace around their
        # separating comma — the serializer preserves the author's line
        # structure (dart-sass behavior). The first selector's flag is
        # always false.
        private def selector_parts(text : String) : {Array(String), Array(Bool)}
          parts = [] of String
          breaks = [] of Bool
          carry = false
          Parser.split_top_level_commas(text).each do |segment|
            stripped = segment.strip
            if stripped.empty?
              carry ||= segment.includes?('\n')
              next
            end
            lead = segment[0, segment.size - segment.lstrip.size]
            breaks << (parts.empty? ? false : (carry || lead.includes?('\n')))
            parts << collapse_ws(stripped)
            carry = segment[segment.rstrip.size..].includes?('\n')
          end
          {parts, breaks}
        end

        # Emits a node into the current sink, reopening the innermost
        # enclosing at-rule first when something else (a bubbled/merged
        # @media) was emitted beside it in the meantime — later content
        # must not serialize above it, or cascade order flips
        # (dart-sass reopens the block the same way).
        private def emit(node : Css::Node) : Nil
          if (frame = @at_frames.last?) && @sink.same?(frame.at.children) &&
             !frame.container.last?.same?(frame.at)
            stale = frame.at
            fresh = Css::AtRule.new(stale.name, stale.prelude)
            frame.container << fresh
            frame.at = fresh
            @sink = fresh.children
            @current_at = fresh if @current_at.same?(stale)
          end
          @sink << node
        end

        private def combine_selectors(parts : Array(String), part_breaks : Array(Bool),
                                      node : Ast::RuleNode) : {Array(String), Array(Bool)}
          parents = @parent_selectors
          if parents.nil?
            parts.each do |part|
              if count_parent_refs(part) > 0
                error_at(node.line, node.column, "top-level selectors may not contain \"&\"")
              end
            end
            return {parts, part_breaks}
          end
          parent_breaks = @parent_breaks

          amps_by_part = parts.map { |part| count_parent_refs(part) }
          amps_by_part.each do |amps|
            next unless amps > 0
            # Cost-check BEFORE building the cross-product: materializing it
            # first is exactly the allocation this guard exists to prevent.
            # Past MAX_PARENT_REF_SLOTS there is no cross-product to size —
            # `parent_combinations` already degrades to a single combo — and
            # the running product is capped rather than raised to a power so
            # the check itself can't overflow.
            next unless amps <= MAX_PARENT_REF_SLOTS
            projected = 1_i64
            amps.times do
              projected *= parents.size
              break if projected > MAX_RULE_SELECTORS
            end
            if projected > MAX_RULE_SELECTORS
              error_at(node.line, node.column,
                "selector expands to more than #{MAX_RULE_SELECTORS} selectors " \
                "(#{parents.size} parent selectors, #{amps} \"&\" references); " \
                "reduce the nesting or the comma-separated parent list")
            end
          end

          # Parent-major ordering (dart-sass): `a, b { c, d {} }` resolves
          # to `a c, a d, b c, b d` — the parent varies slowest. For a
          # multi-`&` part the FIRST `&` slot is the one aligned with the
          # parent loop; the remaining slots run the full parent list.
          result = [] of String
          result_breaks = [] of Bool
          parents.each_with_index do |parent, parent_i|
            # Every combination inherits its parent's OR its child part's
            # line-break flag (dart-sass repeats the break on each
            # combination: `.a,\n.b { .c, .d }` breaks before `.b .c`
            # AND `.b .d`). The overall first selector has no separator.
            pbreak = parent_breaks.try(&.[parent_i]?) || false
            parts.each_with_index do |part, pi|
              # A part carrying `&` loses its own break in dart-sass
              # (`.q &,\n.r &` resolves onto one line); a plain nested
              # part keeps it.
              flag = pbreak || (amps_by_part[pi] == 0 && (part_breaks[pi]? || false))
              push = ->(sel : String) do
                result << sel
                result_breaks << (result.size != 1 && flag)
              end
              amps = amps_by_part[pi]
              if amps == 0
                push.call("#{parent} #{part}")
              elsif amps > MAX_PARENT_REF_SLOTS
                # Degraded single-combo expansion; emit once, on the first
                # parent pass, mirroring parent_combinations' fallback.
                push.call(substitute_parent(part, parents)) if parent_i == 0
              else
                parent_combinations(parents, amps - 1).each do |combo|
                  push.call(substitute_parent(part, [parent] + combo))
                end
              end
              if result.size > MAX_RULE_SELECTORS
                error_at(node.line, node.column,
                  "selector expands to more than #{MAX_RULE_SELECTORS} selectors; " \
                  "reduce the nesting or the comma-separated parent list")
              end
            end
          end
          {result, result_breaks}
        end

        private def template_has_parent_ref?(template : Ast::TextTemplate) : Bool
          template.pieces.any? do |piece|
            case piece
            when String
              piece.includes?('&')
            when Ast::Interp
              # `@at-root #{&}__suffix` — the `&` lives inside the
              # interpolation body (the standard BEM idiom).
              template_has_parent_ref?(piece.inner)
            else
              false
            end
          end
        end

        # Every assignment of `parents` to `slots` independent `&` slots,
        # leftmost varying slowest (dart-sass order). Bounded because the
        # count is exponential in the number of `&` in one selector.
        private def parent_combinations(parents : Array(String), slots : Int32) : Array(Array(String))
          return [parents.dup] if slots > MAX_PARENT_REF_SLOTS
          combos = [[] of String]
          slots.times do
            grown = [] of Array(String)
            combos.each do |combo|
              parents.each { |parent| grown << combo + [parent] }
            end
            combos = grown
          end
          combos
        end

        # Counts `&` occurrences outside quoted strings and attribute
        # brackets — a scan-only twin of substitute_parent.
        private def count_parent_refs(selector : String) : Int32
          chars = selector.chars
          count = 0
          i = 0
          while i < chars.size
            case c = chars[i]
            when '"', '\''
              quote = c
              i += 1
              while i < chars.size
                sc = chars[i]
                if sc == '\\'
                  i += 1
                elsif sc == quote
                  break
                end
                i += 1
              end
            when '['
              while i < chars.size && chars[i] != ']'
                i += 1
              end
            when '&'
              count += 1
            end
            i += 1
          end
          count
        end

        # Replaces top-level `&` with `replacements`, consumed left to
        # right — each occurrence resolves independently, so `& + &` over
        # a parent list yields every pairing. `&` inside quoted strings and
        # attribute brackets is literal.
        private def substitute_parent(selector : String, replacements : Array(String)) : String
          slot = 0
          chars = selector.chars
          String.build do |io|
            i = 0
            while i < chars.size
              c = chars[i]
              case c
              when '"', '\''
                quote = c
                io << c
                i += 1
                while i < chars.size
                  sc = chars[i]
                  io << sc
                  if sc == '\\' && i + 1 < chars.size
                    i += 1
                    io << chars[i]
                  elsif sc == quote
                    break
                  end
                  i += 1
                end
              when '['
                io << c
                i += 1
                while i < chars.size && chars[i] != ']'
                  io << chars[i]
                  i += 1
                end
                io << ']' if i < chars.size
              when '&'
                io << (replacements[slot]? || replacements.last)
                slot += 1
              else
                io << c
              end
              i += 1
            end
          end
        end

        private def eval_declaration(node : Ast::DeclarationNode) : Nil
          name = collapse_ws(resolve_template(node.name, allow_vars: false))
          null_value = false
          value =
            if node.custom_property
              resolve_template(node.value, allow_vars: true).strip
            else
              resolved = resolve_decl_value(node.value)
              null_value = resolved.null_value
              resolved.text
            end
          # A null (or computed-empty) value omits the declaration
          # (dart-sass semantics). Custom properties stay verbatim.
          if !node.custom_property && (null_value || value.empty?) && !node.important
            return
          end
          decl = Css::Decl.new(name, value, node.important)
          if rule = open_rule
            rule.items << decl
          elsif at = @current_at
            at.items << decl
          else
            error_at(node.line, node.column, "declarations may only appear within style rules")
          end
        end

        # The rule new declarations belong to. When nested rules were
        # emitted after the current rule in the same sink, a declaration
        # arriving now must NOT be hoisted back into it — that flips
        # cascade order against source order. Reopen a fresh rule with the
        # same selectors instead (dart-sass behavior).
        private def open_rule : Css::Rule?
          rule = @current_rule
          return unless rule
          sink = @current_rule_sink
          return rule if sink.nil? || sink.last?.same?(rule)
          fresh = Css::Rule.new(rule.selectors, rule.breaks)
          sink << fresh
          @current_rule = fresh
          fresh
        end

        private def emit_comment(text : String) : Nil
          if rule = open_rule
            rule.items << Css::Comment.new(text)
          elsif at = @current_at
            at.items << Css::Comment.new(text)
          else
            emit(Css::Comment.new(text))
          end
        end

        # ---------------------------------------------------------------
        # At-rules
        # ---------------------------------------------------------------

        private def eval_at_rule(node : Ast::RawAtRuleNode) : Nil
          # `@supports (width: calc(1px + 2px))` tests calc SUPPORT —
          # dart-sass deliberately keeps calc() verbatim there; folding it
          # would flip which browsers the block applies to.
          prelude = resolve_prelude(node.prelude, fold_calc: node.name != "supports")

          children = node.children
          unless children
            text = prelude.empty? ? "@#{node.name};" : "@#{node.name} #{prelude};"
            emit(Css::Raw.new(text))
            return
          end

          # `@media` nested inside `@media` merges into one query and
          # bubbles beside the OUTERMOST enclosing media block, matching
          # dart-sass output (`screen` + `(min-width: x)` →
          # `screen and (min-width: x)` at the top level). Queries the
          # string merge can't express (`not …`) keep the nested form —
          # valid modern CSS — instead of being dropped.
          # Only merge when every enclosing at-rule is a @media: with a
          # @supports (or unknown at-rule) in between, bubbling past it
          # would silently drop that condition — keep the nested form.
          container = @sink
          if node.name == "media" && !@at_frames.empty? &&
             @at_frames.all? { |f| f.at.name == "media" }
            # Only fold the innermost enclosing prelude: intermediate
            # frames already store their merged query, so folding every
            # ancestor would duplicate the outer conditions
            # (`(min-width: 1px) and (min-width: 1px) and …`).
            if merged = merge_media_pair(@at_frames.last.at.prelude, prelude)
              prelude = merged
              container = @at_frames[0].container
            end
          end

          at = Css::AtRule.new(node.name, prelude)
          if container.same?(@sink)
            emit(at)
          else
            container << at
          end

          saved_sink = @sink
          saved_rule = @current_rule
          saved_rule_sink = @current_rule_sink
          saved_at = @current_at
          saved_parents = @parent_selectors
          saved_breaks = @parent_breaks
          saved_keyframes = @in_keyframes
          saved_env = @env

          @sink = at.children
          @current_at = at
          @env = Environment.new(saved_env)
          if keyframes?(node.name)
            @current_rule = nil
            @current_rule_sink = nil
            @parent_selectors = nil
            @parent_breaks = nil
            @in_keyframes = true
          elsif (rule = saved_rule) && conditional_group?(node.name)
            # Conditional at-rule nested in a style rule: bubble the
            # at-rule out and re-wrap the declarations in the rule's
            # selector (`.a { @media (x) { color } }` →
            # `@media (x) { .a { color } }`). Descriptor at-rules
            # (@font-face, @page, @property, ...) never take a selector
            # wrapper — their declarations belong to the at-rule itself.
            synthetic = Css::Rule.new(rule.selectors, rule.breaks)
            at.children << synthetic
            @current_rule = synthetic
            @current_rule_sink = at.children
          else
            @current_rule = nil
            @current_rule_sink = nil
          end

          @at_frames << AtFrame.new(at, container)
          begin
            eval_nodes(children)
          ensure
            @at_frames.pop
          end

          @sink = saved_sink
          @current_rule = saved_rule
          @current_rule_sink = saved_rule_sink
          @current_at = saved_at
          @parent_selectors = saved_parents
          @parent_breaks = saved_breaks
          @in_keyframes = saved_keyframes
          @env = saved_env
        end

        private def merge_media_pair(outer : String, inner : String) : String?
          outer_qs = Parser.split_top_level_commas(outer).map { |q| collapse_ws(q) }.reject(&.empty?)
          inner_qs = Parser.split_top_level_commas(inner).map { |q| collapse_ws(q) }.reject(&.empty?)
          return if outer_qs.empty? || inner_qs.empty?
          combined = [] of String
          outer_qs.each do |oq|
            inner_qs.each do |iq|
              if q = merge_media_query(oq, iq)
                combined << q
              elsif media_query_negated?(oq) || media_query_negated?(iq)
                # `not` can't be distributed over `and`; keep nesting.
                # Case-insensitive: CSS media types/keywords are ASCII
                # case-insensitive (`Not print` is the same as `not print`).
                return
              end
              # A plain type conflict (screen × print) drops the pair.
            end
          end
          combined.empty? ? nil : combined.join(", ")
        end

        private def media_query_negated?(query : String) : Bool
          parse_media_query(query).try(&.[:negated]) || false
        end

        # One query each side: `[only|not] [type] [and (feature)...]`.
        private def merge_media_query(outer : String, inner : String) : String?
          o = parse_media_query(outer)
          i = parse_media_query(inner)
          return unless o && i
          return if o[:negated] || i[:negated]
          type =
            if (ot = o[:type]) && (it = i[:type])
              return unless ot == it && o[:modifier] == i[:modifier]
              o[:modifier] + ot
            else
              side = o[:type] ? o : i
              (t = side[:type]) ? side[:modifier] + t : nil
            end
          parts = [] of String
          parts << type if type
          parts.concat(o[:features])
          parts.concat(i[:features])
          return if parts.empty?
          parts.join(" and ")
        end

        # Splits a single media query into modifier/type/features; nil when
        # it doesn't fit the simple shape (`not (...)`, level-4 syntax).
        private def parse_media_query(query : String)
          words = split_media_words(query)
          return if words.empty?
          modifier = ""
          negated = false
          idx = 0
          case words[0].downcase
          when "only"
            modifier = "only "
            idx = 1
          when "not"
            negated = true
            idx = 1
          end
          type = nil
          features = [] of String
          expect_and = false
          while idx < words.size
            word = words[idx]
            if word.starts_with?('(')
              features << word
            elsif word.downcase == "and"
              idx += 1
              next
            elsif type.nil? && features.empty? && !expect_and
              type = word
            else
              return
            end
            expect_and = true
            idx += 1
          end
          return if negated && !features.empty? && type.nil?
          {modifier: modifier, negated: negated, type: type, features: features}
        end

        # Media query words: feature parens are single words.
        private def split_media_words(query : String) : Array(String)
          words = [] of String
          buf = String::Builder.new
          depth = 0
          query.each_char do |c|
            if c == '('
              depth += 1
              buf << c
            elsif c == ')'
              depth -= 1
              buf << c
            elsif c.ascii_whitespace? && depth == 0
              word = buf.to_s
              words << word unless word.empty?
              buf = String::Builder.new
            else
              buf << c
            end
          end
          word = buf.to_s
          words << word unless word.empty?
          words
        end

        private def keyframes?(name : String) : Bool
          name == "keyframes" || name.ends_with?("-keyframes")
        end

        # At-rules whose body is a descriptor block: the declarations belong
        # to the at-rule itself, so bubbling one out of a style rule must
        # NOT wrap them in the parent selector.
        #
        # This is a denylist on purpose. Everything else — @media,
        # @supports, @layer, @container, @starting-style, and any at-rule
        # newer than this compiler — is a grouping at-rule and keeps the
        # selector. An allowlist silently dropped the selector for anything
        # it hadn't heard of, emitting a selector-less declaration that
        # browsers discard.
        DESCRIPTOR_AT_RULES = %w[font-face page property counter-style font-palette-values viewport]

        private def conditional_group?(name : String) : Bool
          !DESCRIPTOR_AT_RULES.includes?(name)
        end

        # ---------------------------------------------------------------
        # Mixins & @content
        # ---------------------------------------------------------------

        private def eval_include(node : Ast::IncludeNode) : Nil
          closure = lookup_mixin(node)

          @include_depth += 1
          if @include_depth > MAX_INCLUDE_DEPTH
            error_at(node.line, node.column, "too much recursion in @include")
          end

          call_env = Environment.new(closure.env)
          positional, kwargs, rest_sep = collect_args(node.args, "mixin #{node.name}", node.line, node.column)
          extra = bind_params(closure.node.params, positional, kwargs, call_env,
            "mixin #{node.name}", node.line, node.column, rest_sep: rest_sep)

          content =
            if body = node.body
              # dart-sass parity: passing a block to a mixin whose body never
              # reaches `@content` is an error — silently discarding the
              # block's styles (the alternative) loses user CSS on a typo'd
              # or refactored mixin with no signal at all.
              unless accepts_content?(closure.node.body)
                error_at(node.line, node.column,
                  "mixin #{node.name} doesn't accept a content block (no @content in its body)")
              end
              ContentBlock.new(body, @env, @content, @path, node.using_params)
            end

          saved_env = @env
          saved_content = @content
          saved_path = @path
          saved_kw = @keywords_accessed
          @env = call_env
          @content = content
          @path = closure.path
          @keywords_accessed = Set(String).new
          begin
            eval_nodes(closure.node.body)
            reject_unused_kwargs(extra, closure.node.params, "mixin #{node.name}",
              node.line, node.column)
          ensure
            @env = saved_env
            @content = saved_content
            @path = saved_path
            @keywords_accessed = saved_kw
            @include_depth -= 1
          end
        end

        private def lookup_mixin(node : Ast::IncludeNode) : MixinClosure
          if ns = node.namespace
            mod = @env.module?(ns)
            error_at(node.line, node.column, "there is no module namespace \"#{ns}\"") unless mod
            mod.mixins[Sass.normalize_ident(node.name)]? ||
              error_at(node.line, node.column, "undefined mixin: \"#{ns}.#{node.name}\"")
          else
            @env.lookup_mixin(node.name) ||
              error_at(node.line, node.column, "undefined mixin: \"#{node.name}\"")
          end
        end

        # Resolves call-site arguments (in the caller's scope) into
        # positional strings and keyword strings; `$value...` spreads
        # lists into positionals and maps into keywords. The third result
        # is the separator of a spread list, so a variadic parameter that
        # absorbs it keeps the original separator (`$lst: 4 5 6` spread
        # into `$rest...` must stay space-separated).
        private def collect_args(args : Array(Ast::Arg), what : String,
                                 line : Int32, column : Int32) : {Array(String), Hash(String, String), ListV::Sep?}
          positional = [] of String
          kwargs = {} of String => String
          rest_sep = nil.as(ListV::Sep?)

          args.each do |arg|
            value = resolve_value(arg.value) # evaluated in the caller's scope
            if arg.spread
              if sep = spread_into(value, positional, kwargs, line, column)
                rest_sep = sep
              end
              # Spreading a variadic arglist onward forwards its keyword
              # arguments too (`@include inner($args...)` — dart-sass
              # semantics). The keywords live in the hidden side-channel
              # the variadic binding wrote.
              if (pieces = arg.value.pieces).size == 1 && (ref = pieces[0].as?(Ast::VarRef)) && ref.namespace.nil?
                rest_name = Sass.normalize_ident(ref.name)
                if stored = @env.lookup_var(KEYWORDS_VAR_PREFIX + rest_name)
                  # Forwarding `$args...` counts as using the extra keywords.
                  @keywords_accessed << rest_name
                  if map = Expr.coerce(stored).as?(MapV)
                    map.entries.each do |entry|
                      key = entry.key
                      next unless key.is_a?(Str)
                      kwargs[Sass.normalize_ident(key.text)] ||= value_storage(entry.value)
                    end
                  end
                end
              end
            elsif name = arg.name
              name = Sass.normalize_ident(name)
              if kwargs.has_key?(name)
                error_at(line, column, "duplicate argument $#{name}")
              end
              kwargs[name] = value
            else
              unless kwargs.empty?
                error_at(line, column, "positional arguments must precede keyword arguments")
              end
              positional << value
            end
          end
          {positional, kwargs, rest_sep}
        end

        # Returns the spread list's separator (nil for maps/scalars).
        private def spread_into(value : String, positional : Array(String),
                                kwargs : Hash(String, String), line : Int32, column : Int32) : ListV::Sep?
          spread = Expr.coerce(value)
          case spread
          when MapV
            spread.entries.each do |entry|
              key = entry.key
              unless key.is_a?(Str)
                error_at(line, column, "map keys in a spread argument must be strings")
              end
              kwargs[Sass.normalize_ident(key.text)] = value_storage(entry.value)
            end
            nil
          when ListV
            unless kwargs.empty?
              error_at(line, column, "positional arguments must precede keyword arguments")
            end
            spread.items.each { |item| positional << value_storage(item) }
            spread.sep
          else
            unless kwargs.empty?
              error_at(line, column, "positional arguments must precede keyword arguments")
            end
            positional << value
            nil
          end
        end

        # Binds arguments to parameters (shared by mixins and functions).
        # `soft: true` raises SoftEvalError instead of located errors —
        # function calls happen inside expression evaluation, where
        # lenient contexts fall back and strict contexts add locations.
        # Hidden variable prefix carrying a variadic parameter's keyword
        # arguments (`meta.keywords($args)` / spread forwarding). `@` can
        # never appear in a user identifier, so the side-channel is
        # unreachable from stylesheet code.
        KEYWORDS_VAR_PREFIX = "@kw:"

        private def bind_params(params : Array(Ast::Param), positional : Array(String),
                                kwargs : Hash(String, String), call_env : Environment,
                                what : String, line : Int32, column : Int32,
                                soft : Bool = false, rest_sep : ListV::Sep? = nil) : Hash(String, String)
          param_names = params.map { |p| Sass.normalize_ident(p.name) }
          variadic = params.last?.try(&.variadic) || false
          fixed = variadic ? params.size - 1 : params.size

          # Keyword arguments no fixed parameter declares flow into the
          # variadic arglist's keyword store (dart-sass semantics) — only
          # a non-variadic signature rejects them.
          extra_kwargs = {} of String => String
          kwargs.each do |name, value|
            unless param_names.includes?(name)
              unless variadic
                bind_error("no parameter named $#{name} in #{what}", soft, line, column)
              end
              extra_kwargs[name] = value
            end
          end
          if variadic && kwargs.has_key?(param_names.last)
            bind_error("variadic parameter $#{params.last.name} can't be passed by name", soft, line, column)
          end
          if positional.size > fixed && !variadic
            bind_error("#{what} takes #{fixed} argument(s) but #{positional.size} were passed", soft, line, column)
          end

          params.each_with_index do |param, i|
            param_name = param_names[i]
            if param.variadic
              rest = positional.size > fixed ? positional[fixed..] : [] of String
              joiner =
                case rest_sep
                in nil, ListV::Sep::Comma then ", "
                in ListV::Sep::Space      then " "
                in ListV::Sep::Slash      then " / "
                end
              call_env.variables[param_name] = rest.empty? ? "()" : rest.join(joiner)
              call_env.variables[KEYWORDS_VAR_PREFIX + param_name] = keywords_storage(extra_kwargs)
              next
            end
            value =
              if i < positional.size
                if kwargs.has_key?(param_name)
                  bind_error("$#{param.name} was passed both by position and by name", soft, line, column)
                end
                positional[i]
              elsif kw = kwargs[param_name]?
                kw
              elsif default = param.default
                # Defaults see earlier parameters (dart-sass semantics).
                saved = @env
                @env = call_env
                begin
                  resolve_value(default)
                ensure
                  @env = saved
                end
              else
                bind_error("missing argument $#{param.name} for #{what}", soft, line, column)
              end
            call_env.variables[param_name] = value
          end
          extra_kwargs
        end

        private def reject_unused_kwargs(extra : Hash(String, String), params : Array(Ast::Param),
                                         what : String, line : Int32, column : Int32,
                                         soft : Bool = false) : Nil
          return if extra.empty?
          rest = params.last?
          return unless rest && rest.variadic
          rest_name = Sass.normalize_ident(rest.name)
          return if @keywords_accessed.includes?(rest_name)
          bind_error("no parameter named $#{extra.keys.first} in #{what}", soft, line, column)
        end

        private def bind_error(message : String, soft : Bool, line : Int32, column : Int32) : NoReturn
          raise SoftEvalError.new(message) if soft
          error_at(line, column, message)
        end

        # Serializes leftover keyword arguments as a map storage string.
        # Values containing top-level commas wrap in structural parens so
        # they survive the map's own comma separators on re-parse.
        private def keywords_storage(kwargs : Hash(String, String)) : String
          return "()" if kwargs.empty?
          "(" + kwargs.map { |k, v| "#{k}: #{v.includes?(',') ? "(#{v})" : v}" }.join(", ") + ")"
        end

        # True when the mixin body can reach `@content`: a lexically nested
        # `@content` anywhere except inside a nested `@mixin` definition
        # (whose `@content` belongs to that inner mixin — dart-sass scoping).
        # Include bodies DO count: `@mixin a { @include b { @content } }`
        # passes a's content through b.
        private def accepts_content?(nodes : Array(Ast::Node)) : Bool
          nodes.any? do |node|
            case node
            when Ast::ContentNode
              true
            when Ast::RuleNode
              accepts_content?(node.children)
            when Ast::IncludeNode
              node.body.try { |b| accepts_content?(b) } || false
            when Ast::RawAtRuleNode
              node.children.try { |c| accepts_content?(c) } || false
            when Ast::IfNode
              node.branches.any? { |branch| accepts_content?(branch.body) }
            when Ast::EachNode, Ast::ForNode, Ast::WhileNode
              accepts_content?(node.body)
            when Ast::AtRootNode
              accepts_content?(node.children)
            else
              false
            end
          end
        end

        private def eval_content(node : Ast::ContentNode) : Nil
          block = @content
          return unless block # @include without a body: @content emits nothing

          # `@content(args)` arguments evaluate in the MIXIN body's scope
          # and bind to the include's `using (...)` parameters in the
          # content block's scope (dart-sass semantics).
          content_env = Environment.new(block.env)
          extra = {} of String => String
          if !node.args.empty? || !block.params.empty?
            positional, kwargs, rest_sep = collect_args(node.args, "@content", node.line, node.column)
            extra = bind_params(block.params, positional, kwargs, content_env,
              "the content block", node.line, node.column, rest_sep: rest_sep)
          end

          saved_env = @env
          saved_content = @content
          saved_path = @path
          saved_kw = @keywords_accessed
          @env = content_env
          @content = block.outer
          @path = block.path
          @keywords_accessed = Set(String).new
          begin
            eval_nodes(block.nodes)
            reject_unused_kwargs(extra, block.params, "the content block", node.line, node.column)
          ensure
            @env = saved_env
            @content = saved_content
            @path = saved_path
            @keywords_accessed = saved_kw
          end
        end

        # Nested property block: `font: 12px serif { family: sans; }`
        # emits `font: 12px serif` plus `font-family: sans`, prefixing
        # recursively. Only declarations (and nested blocks/comments) may
        # appear inside — anything else is an error, matching dart-sass.
        private def eval_nested_props(node : Ast::NestedPropsNode) : Nil
          if value = node.value
            eval_declaration(Ast::DeclarationNode.new(
              node.name, value, node.important, false, node.line, node.column))
          end
          node.children.each do |child|
            case child
            when Ast::DeclarationNode
              eval_declaration(Ast::DeclarationNode.new(
                prefix_property(node.name, child.name), child.value,
                child.important, child.custom_property, child.line, child.column))
            when Ast::NestedPropsNode
              eval_nested_props(Ast::NestedPropsNode.new(
                prefix_property(node.name, child.name), child.value,
                child.important, child.children, child.line, child.column))
            when Ast::CommentNode
              emit_comment(comment_text(child))
            when Ast::VarDeclNode, Ast::MessageNode
              eval_node(child)
            else
              # Control flow / includes inside a nested property block
              # would emit their declarations WITHOUT the prefix — a
              # silent misrender. Refuse instead.
              error_at(child.line, child.column,
                "only declarations are allowed inside a nested property block")
            end
          end
        end

        # `font` + `family` → `font-family`, preserving interpolation in
        # either template.
        private def prefix_property(outer : Ast::TextTemplate, inner : Ast::TextTemplate) : Ast::TextTemplate
          pieces = outer.pieces + [dash_piece] + inner.pieces
          Ast::TextTemplate.new(pieces, inner.line, inner.column)
        end

        private def dash_piece : Ast::Piece
          "-".as(Ast::Piece)
        end

        # ---------------------------------------------------------------
        # Control flow
        # ---------------------------------------------------------------

        # Flow-control bodies introduce a transparent variable scope:
        # new declarations stay local, but assignments to outer names —
        # globals included — write through (dart-sass flow-control
        # scoping; loop counters depend on it).
        private def scoped(& : -> Nil) : Nil
          saved = @env
          @env = Environment.new(saved, flow_control: true)
          begin
            yield
          ensure
            @env = saved
          end
        end

        private def eval_if(node : Ast::IfNode) : Nil
          node.branches.each do |branch|
            condition = branch.condition
            next unless condition.nil? || eval_expr!(condition).truthy?
            scoped { eval_nodes(branch.body) }
            break
          end
        end

        private def eval_each(node : Ast::EachNode) : Nil
          value = eval_expr!(node.list)
          items =
            case value
            when ListV
              value.items
            when MapV
              value.entries.map { |e| ListV.new([e.key, e.value], ListV::Sep::Space).as(Value) }
            when NullV
              # dart-sass iterates null once, as a single-item list. The
              # `$list: null !default` + `@each` guard is a normal idiom;
              # refusing it failed the whole build.
              [value]
            else
              [value]
            end
          items.each do |item|
            count_loop_iteration(node.line, node.column)
            scoped do
              bind_each_vars(node.vars, item)
              eval_nodes(node.body)
            end
          end
        end

        private def bind_each_vars(vars : Array(String), item : Value) : Nil
          if vars.size == 1
            @env.variables[Sass.normalize_ident(vars[0])] = value_storage(item)
            return
          end
          parts =
            case item
            when ListV then item.items
            else            [item]
            end
          vars.each_with_index do |name, i|
            @env.variables[Sass.normalize_ident(name)] = value_storage(parts[i]? || NullV.new)
          end
        end

        private def eval_for(node : Ast::ForNode) : Nil
          from_n = for_bound(node.from, node)
          to_n = for_bound(node.to, node)
          unless from_n.compatible_unit?(to_n)
            error_at(node.line, node.column,
              "@for range has incompatible units: #{from_n.to_css} and #{to_n.to_css}")
          end
          unit = from_n.result_unit(to_n)
          from_i = int_bound(from_n, node)
          to_i = int_bound(to_n, node)
          name = Sass.normalize_ident(node.var)

          iterate = ->(i : Int32) do
            count_loop_iteration(node.line, node.column)
            scoped do
              @env.variables[name] = Number.format(i.to_f) + unit
              eval_nodes(node.body)
            end
          end

          if from_i <= to_i
            last = node.exclusive ? to_i - 1 : to_i
            from_i.upto(last) { |i| iterate.call(i) }
          else
            # dart-sass iterates downward when from > to.
            last = node.exclusive ? to_i + 1 : to_i
            from_i.downto(last) { |i| iterate.call(i) }
          end
        end

        private def for_bound(template : Ast::TextTemplate, node : Ast::ForNode) : Number
          value = eval_expr!(template)
          case value
          when Number
            value
          else
            error_at(node.line, node.column, "@for bounds must be numbers, got #{value.to_css.inspect}")
          end
        end

        private def int_bound(bound : Number, node : Ast::ForNode) : Int32
          bound.int_value("@for range")
        rescue ex : SoftEvalError
          error_at(node.line, node.column, ex.message || "invalid @for range")
        end

        private def eval_while(node : Ast::WhileNode) : Nil
          iterations = 0
          while eval_expr!(node.condition).truthy?
            iterations += 1
            if iterations > MAX_WHILE_ITERATIONS
              error_at(node.line, node.column,
                "@while exceeded #{MAX_WHILE_ITERATIONS} iterations (infinite loop?)")
            end
            count_loop_iteration(node.line, node.column)
            scoped { eval_nodes(node.body) }
          end
        end

        private def eval_message(node : Ast::MessageNode) : Nil
          text = message_text(node.value)
          location = "#{@path}:#{node.line}:#{node.column}"
          case node.kind
          when :debug
            Logger.debug "Sass: #{location}: DEBUG: #{text}"
          when :warn
            Logger.warn "Sass: #{location}: WARNING: #{text}"
          else
            error_at(node.line, node.column, text)
          end
        end

        private def message_text(template : Ast::TextTemplate) : String
          value = Expr::Evaluator.new(self, strict: true, force_div: true).eval(Expr.parse!(template))
          value.is_a?(Str) ? value.text : Builtins.inspect_value(value)
        rescue SoftEvalError
          resolve_value(template)
        end

        # `@at-root` re-evaluates its body outside style-rule nesting but
        # inside any surrounding at-rule (the flat sink makes that the
        # natural behavior). A query picks which contexts are escaped:
        # `(without: media)` keeps selector nesting but hoists out of
        # `@media`, `(with: rule)` keeps rules and escapes all at-rules.
        private def eval_at_root(node : Ast::AtRootNode) : Nil
          if query = node.query
            eval_at_root_query(node, query)
            return
          end
          saved_rule = @current_rule
          saved_parents = @parent_selectors
          saved_breaks = @parent_breaks
          @current_rule = nil
          @parent_selectors = nil
          @parent_breaks = nil
          begin
            if selector = node.selector
              # `&` in an `@at-root` selector still refers to the enclosing
              # rule (`.parent { @at-root .child & { } }` → `.child
              # .parent`, `@at-root #{&}__suffix` → `.parent__suffix`) —
              # expose the parents for resolution. But the result is a
              # TOP-LEVEL rule: a selector without `&` left in it must not
              # be re-nested under the parents.
              if template_has_parent_ref?(selector)
                @parent_selectors = saved_parents
                @parent_breaks = saved_breaks
              end
              eval_at_root_rule(selector, node, saved_parents)
            else
              # A plain block scope, not `scoped`: `@at-root` is not a
              # flow-control rule, so assignments inside it must not write
              # through to the enclosing scope the way `@if`/`@while` do.
              saved_env = @env
              @env = Environment.new(saved_env)
              begin
                eval_nodes(node.children)
              ensure
                @env = saved_env
              end
            end
          ensure
            @current_rule = saved_rule
            @parent_selectors = saved_parents
            @parent_breaks = saved_breaks
          end
        end

        # The `@at-root .sel { }` rule: literal `&` substitutes the parent
        # selectors, but the resolved parts stand at the root as-is —
        # unlike a nested rule, a part without `&` takes no parent prefix.
        private def eval_at_root_rule(selector : Ast::TextTemplate, node : Ast::AtRootNode,
                                      parents : Array(String)?) : Nil
          text = resolve_template(selector, allow_vars: false)
          parts, part_breaks = selector_parts(text)
          error_at(node.line, node.column, "expected selector") if parts.empty?

          selectors = [] of String
          breaks = [] of Bool
          parts.each_with_index do |part, part_i|
            # Each combination repeats its part's break flag (same rule as
            # combine_selectors); the overall first selector never breaks.
            push = ->(sel : String) do
              selectors << sel
              breaks << (selectors.size != 1 && (part_breaks[part_i]? || false))
            end
            amps = count_parent_refs(part)
            if amps == 0
              push.call(part)
            elsif parents.nil?
              error_at(node.line, node.column, "top-level selectors may not contain \"&\"")
            else
              if amps <= MAX_PARENT_REF_SLOTS
                projected = 1_i64
                amps.times do
                  projected *= parents.size
                  break if projected > MAX_RULE_SELECTORS
                end
                if projected > MAX_RULE_SELECTORS
                  error_at(node.line, node.column,
                    "selector expands to more than #{MAX_RULE_SELECTORS} selectors " \
                    "(#{parents.size} parent selectors, #{amps} \"&\" references); " \
                    "reduce the nesting or the comma-separated parent list")
                end
              end
              combos =
                if amps <= MAX_PARENT_REF_SLOTS
                  parent_combinations(parents, amps)
                else
                  [parents.dup]
                end
              combos.each { |combo| push.call(substitute_parent(part, combo)) }
            end
            if selectors.size > MAX_RULE_SELECTORS
              error_at(node.line, node.column,
                "selector expands to more than #{MAX_RULE_SELECTORS} selectors; " \
                "reduce the comma-separated parent list")
            end
          end

          rule = Css::Rule.new(selectors, breaks)
          emit(rule)
          saved_rule = @current_rule
          saved_rule_sink = @current_rule_sink
          saved_parents = @parent_selectors
          saved_breaks = @parent_breaks
          saved_env = @env
          @current_rule = rule
          @current_rule_sink = @sink
          @parent_selectors = selectors
          @parent_breaks = breaks
          @env = Environment.new(saved_env)
          begin
            eval_nodes(node.children)
          ensure
            @current_rule = saved_rule
            @current_rule_sink = saved_rule_sink
            @parent_selectors = saved_parents
            @parent_breaks = saved_breaks
            @env = saved_env
          end
          # A rule lifted to the root is its own output group — dart-sass
          # separates it from what follows with a blank line.
          if @at_frames.empty? && (last = @sink.last?)
            last.group_end = true
          end
        end

        # `@at-root (with: ...)` / `(without: ...)`. Escaped at-rule
        # contexts are left by re-targeting the sink at the container of
        # the outermost escaped frame; kept style-rule nesting means the
        # parent selectors stay visible so nested rules resolve normally.
        private def eval_at_root_query(node : Ast::AtRootNode, query : Ast::AtRootQuery) : Nil
          target_sink = @sink
          kept_frames = @at_frames
          if idx = @at_frames.index { |frame| query.escapes_at?(frame.at.name) }
            target_sink = @at_frames[idx].container
            kept_frames = @at_frames[0...idx]
          end

          saved_sink = @sink
          saved_frames = @at_frames
          saved_rule = @current_rule
          saved_rule_sink = @current_rule_sink
          saved_parents = @parent_selectors
          saved_breaks = @parent_breaks
          saved_at = @current_at
          saved_env = @env

          @sink = target_sink
          @at_frames = kept_frames
          @current_at = kept_frames.last?.try(&.at)
          @current_rule = nil
          @current_rule_sink = nil
          @parent_selectors = query.escapes_rules? ? nil : saved_parents
          @parent_breaks = query.escapes_rules? ? nil : saved_breaks
          @env = Environment.new(saved_env)
          begin
            if query.escapes_rules? || saved_parents.nil?
              eval_nodes(node.children)
            else
              # Rules kept: re-wrap the body in the enclosing selectors so
              # declarations keep their rule (`e { @at-root (without:
              # media) { f {} } }` → `e f` outside the media).
              rule = Css::Rule.new(saved_parents, saved_breaks || [] of Bool)
              emit(rule)
              @current_rule = rule
              @current_rule_sink = @sink
              @parent_selectors = saved_parents
              @parent_breaks = saved_breaks
              eval_nodes(node.children)
              # Same group rule as eval_at_root_rule: content escaped to
              # the root separates from what follows.
              if @at_frames.empty? && (last = @sink.last?)
                last.group_end = true
              end
            end
          ensure
            @sink = saved_sink
            @at_frames = saved_frames
            @current_rule = saved_rule
            @current_rule_sink = saved_rule_sink
            @parent_selectors = saved_parents
            @parent_breaks = saved_breaks
            @current_at = saved_at
            @env = saved_env
          end
        end

        # ---------------------------------------------------------------
        # @extend
        # ---------------------------------------------------------------

        # Records the enclosing rule's selectors as extenders of each
        # target; application happens document-wide after evaluation, once
        # every rule (own file, @use'd modules, @imports) is in the sink.
        private def eval_extend(node : Ast::ExtendNode) : Nil
          rule = @current_rule
          if rule.nil? || @in_keyframes
            error_at(node.line, node.column, "@extend may only be used within style rules")
          end
          text = resolve_template(node.selector, allow_vars: false)
          targets = Parser.split_top_level_commas(text).map { |s| collapse_ws(s) }.reject(&.empty?)
          error_at(node.line, node.column, "expected selector after @extend") if targets.empty?
          # Snapshot the selectors: the apply pass appends to rule selector
          # arrays, and a request must not iterate an extender list that is
          # growing under it (self-extension aliases the two). Chains still
          # resolve through the per-rule fixpoint.
          extenders = rule.selectors.dup
          extender_breaks = rule.breaks.dup
          targets.each do |target|
            @extends << Extend::Request.new(extenders, target, node.optional,
              @path, node.line, node.column, extender_breaks)
          end
        end

        private def apply_extends : Nil
          return if @extends.empty?
          matched = Array(Bool).new(@extends.size, false)
          extend_nodes(@sink, matched)
          @extends.each_with_index do |req, i|
            next if req.optional || matched[i]
            raise SyntaxError.new(
              "@extend target #{req.target.inspect} was not found " \
              "(add \"!optional\" to tolerate a missing target)",
              req.path, req.line, req.column)
          end
        end

        private def extend_nodes(nodes : Array(Css::Node), matched : Array(Bool)) : Nil
          nodes.each do |node|
            case node
            when Css::Rule
              extend_rule(node, matched)
            when Css::AtRule
              extend_nodes(node.children, matched) unless keyframes?(node.name)
            end
          end
        end

        # Grows the rule's selector list to a local fixpoint: selectors a
        # request adds are themselves candidates for other requests, which
        # is what makes chained extends (`.c {@extend .b} .b {@extend .a}`)
        # resolve. Terminates because additions are deduplicated and capped.
        private def extend_rule(rule : Css::Rule, matched : Array(Bool)) : Nil
          selectors = rule.selectors
          breaks = rule.breaks
          # Keep the flags index-aligned before inserting mid-list.
          while breaks.size < selectors.size
            breaks << false
          end
          seen = selectors.to_set
          i = 0
          while i < selectors.size
            sel = selectors[i]
            @extends.each_with_index do |req, ri|
              results = Extend.extend_selector(sel, req.target, req.extenders)
              next unless results
              matched[ri] = true
              # The cursor resets PER REQUEST: each request's additions go
              # directly after the extended selector, so later requests
              # land closer to it and push earlier ones right — dart-sass
              # 1.103 emits `.b, .a` for `.a { @extend %p } .b { @extend
              # %p }` (verified empirically; per-selector source order is
              # NOT preserved).
              offset = 1
              results.each do |(added, ext_i)|
                next if seen.includes?(added)
                seen << added
                # Insert right after the selector that was extended —
                # dart-sass keeps the additions in place (the placeholder
                # scrub then leaves `.uses, .direct`, not `.direct, .uses`)
                # — with the extender's OR the extended selector's break
                # flag (same OR rule as selector resolution): a multi-line
                # extending rule keeps its structure (`.x,\n.y { @extend
                # .t }` emits `.t, .x,\n.y`), and extending a broken
                # selector stays broken.
                flag = (ext_i >= 0 && (req.breaks[ext_i]? || false)) || (breaks[i]? || false)
                selectors.insert(i + offset, added)
                breaks.insert(i + offset, flag)
                offset += 1
                if selectors.size > MAX_RULE_SELECTORS
                  raise SyntaxError.new(
                    "@extend expanded a rule to more than #{MAX_RULE_SELECTORS} selectors " \
                    "(mutually recursive extends?)",
                    req.path, req.line, req.column)
                end
              end
            end
            i += 1
          end
        end

        # ---------------------------------------------------------------
        # Functions
        # ---------------------------------------------------------------

        # Strict expression evaluation for control-flow contexts: every
        # failure is a located error.
        private def eval_expr!(template : Ast::TextTemplate) : Value
          node = Expr.parse!(template)
          Expr::Evaluator.new(self, strict: true, force_div: true).eval(node)
        rescue ex : SoftEvalError
          error_at(template.line, template.column, ex.message || "invalid expression")
        end

        # Calls a user @function body. Binding/arity failures raise
        # SoftEvalError so lenient value contexts fall back and strict
        # contexts report a located error.
        private def call_user_function(closure : FunctionClosure, name : String,
                                       args : Array(Value), kwargs : Hash(String, Value)) : Value
          @call_depth += 1
          if @call_depth > MAX_CALL_DEPTH
            @call_depth -= 1
            raise SoftEvalError.new("too much recursion in function #{name}")
          end
          begin
            call_env = Environment.new(closure.env)
            positional = args.map { |a| value_storage(a) }
            kw = {} of String => String
            kwargs.each { |k, v| kw[k] = value_storage(v) }
            extra = bind_params(closure.node.params, positional, kw, call_env,
              "function #{name}", closure.node.line, closure.node.column, soft: true)

            saved_env = @env
            saved_path = @path
            saved_in_function = @in_function
            saved_kw = @keywords_accessed
            @env = call_env
            @path = closure.path
            @in_function = true
            @keywords_accessed = Set(String).new
            begin
              eval_nodes(closure.node.body)
              raise SoftEvalError.new("function #{name} finished without @return")
            rescue ex : ReturnSignal
              reject_unused_kwargs(extra, closure.node.params, "function #{name}",
                closure.node.line, closure.node.column, soft: true)
              ex.value
            ensure
              @env = saved_env
              @path = saved_path
              @in_function = saved_in_function
              @keywords_accessed = saved_kw
            end
          ensure
            @call_depth -= 1
          end
        end

        # ---------------------------------------------------------------
        # @use / @import
        # ---------------------------------------------------------------

        private def eval_use(node : Ast::UseNode) : Nil
          config = {} of String => String
          node.config.each do |entry|
            name = Sass.normalize_ident(entry.name)
            if config.has_key?(name)
              error_at(node.line, node.column, "duplicate configuration $#{entry.name}")
            end
            # Evaluated in the caller's scope, before the module loads.
            config[name] = resolve_value(entry.value)
          end
          mod = load_module(node.url, node.line, node.column, config)
          register_module(node, mod)
        end

        # Loads (or returns the cached) module for a @use/@forward url.
        # `sass:` urls resolve to the built-in modules.
        #
        # `implicit` marks a configuration that came from an importing
        # file's globals rather than a `with (...)` clause (see
        # `@import_config`). dart-sass applies such a configuration only to
        # the names the module declares with `!default`, never errors on
        # names it does not declare, and silently ignores it when the
        # module was already loaded — an explicit `with` does all three.
        private def load_module(url : String, line : Int32, column : Int32,
                                config : Hash(String, String), implicit : Bool = false) : SassModule
          if url.starts_with?("sass:")
            name = url.lchop("sass:")
            mod = BUILTIN_MODULES[name]?
            error_at(line, column, "unknown built-in module \"sass:#{name}\"") unless mod
            error_at(line, column, "built-in modules can't be configured") unless config.empty? || implicit
            return mod
          end

          canonical, source = @importer.load(url, @path, @path, line, column)
          if mod = @loaded_modules[canonical]?
            unless config.empty? || implicit
              error_at(line, column,
                "#{@importer.display_path(canonical)} was already loaded and can't be configured a second time")
            end
            return mod
          end

          check_cycle(canonical, line, column)
          display = @importer.display_path(canonical)
          sheet = Parser.parse(source, display)
          seed = config
          if implicit
            # Only `!default` declarations consume an implicit configuration;
            # a name the module assigns unconditionally keeps its own value.
            # The unfiltered configuration still travels on through this
            # module's own `@forward`s (a forwarding index declares nothing
            # itself), so filter the seed, not `config`.
            defaults = Set(String).new
            collect_default_decls(sheet.children, defaults)
            seed = config.select { |name, _| defaults.includes?(name) }
          elsif !config.empty?
            validate_configurable(sheet, config, url, line, column)
          end

          saved_env = @env
          saved_sink = @sink
          saved_rule = @current_rule
          saved_at = @current_at
          saved_parents = @parent_selectors
          saved_parent_breaks = @parent_breaks
          saved_content = @content
          saved_keyframes = @in_keyframes
          saved_path = @path
          saved_fwd_vars = @forward_variables
          saved_fwd_mixins = @forward_mixins
          saved_fwd_fns = @forward_functions
          saved_import_config = @import_config
          # A `@forward` inside this module passes the implicit configuration
          # on (dart-sass `Configuration#throughForward`); a `@use` starts
          # from nothing, even when reached through an import.
          @import_config = implicit ? config : nil

          module_env = Environment.new
          seed.each { |name, value| module_env.variables[name] = value }
          module_sink = [] of Css::Node
          @env = module_env
          @sink = module_sink
          @current_rule = nil
          @current_at = nil
          @parent_selectors = nil
          @parent_breaks = nil
          @content = nil
          @in_keyframes = false
          @path = display
          @forward_variables = {} of String => String
          @forward_mixins = {} of String => MixinClosure
          @forward_functions = {} of String => SassFn
          @load_stack << canonical
          begin
            eval_nodes(sheet.children)
            # Own root members win over forwarded ones on name collisions.
            mod = SassModule.new(
              export_members(@forward_variables.merge(module_env.variables)),
              export_members(@forward_mixins.merge(module_env.mixins)),
              export_members(@forward_functions.merge(module_env.functions)))
          ensure
            @load_stack.pop
            @env = saved_env
            @sink = saved_sink
            @current_rule = saved_rule
            @current_at = saved_at
            @parent_selectors = saved_parents
            @parent_breaks = saved_parent_breaks
            @content = saved_content
            @in_keyframes = saved_keyframes
            @path = saved_path
            @forward_variables = saved_fwd_vars
            @forward_mixins = saved_fwd_mixins
            @forward_functions = saved_fwd_fns
            @import_config = saved_import_config
          end

          @loaded_modules[canonical] = mod
          # A module's CSS is emitted once, spliced in where the `@use` was
          # reached — which is before the code that uses it, since `@use`
          # precedes the using file's own rules. Collecting it into a
          # document-wide buffer instead would hoist it above rules that ran
          # *earlier* (e.g. when the `@use` is reached through an `@import`),
          # flipping the cascade winner between equal-specificity selectors.
          @sink.concat(module_sink)
          mod
        end

        # `@use ... with (...)` can only configure variables the module
        # itself declares with `!default`; modules that @forward are a
        # clear error rather than a silently ignored configuration.
        private def validate_configurable(sheet : Ast::Stylesheet, config : Hash(String, String),
                                          url : String, line : Int32, column : Int32) : Nil
          if sheet.children.any?(Ast::ForwardNode)
            error_at(line, column,
              "configuring \"#{url}\" is not supported because it uses @forward")
          end
          defaults = Set(String).new
          collect_default_decls(sheet.children, defaults)
          config.each_key do |name|
            unless defaults.includes?(name)
              error_at(line, column,
                "$#{name} is not declared with !default in \"#{url}\" and can't be configured")
            end
          end
        end

        private def collect_default_decls(nodes : Array(Ast::Node), set : Set(String)) : Nil
          nodes.each do |node|
            case node
            when Ast::VarDeclNode
              set << Sass.normalize_ident(node.name) if node.default
            when Ast::IfNode
              node.branches.each { |branch| collect_default_decls(branch.body, set) }
            when Ast::EachNode
              collect_default_decls(node.body, set)
            when Ast::ForNode
              collect_default_decls(node.body, set)
            when Ast::WhileNode
              collect_default_decls(node.body, set)
            end
          end
        end

        # @forward: load the module (emitting its CSS once) and stage its
        # members — filtered by show/hide, optionally prefixed — as the
        # current module's re-exports. Members do NOT enter local scope.
        # show/hide match the *prefixed* names (dart-sass semantics).
        private def eval_forward(node : Ast::ForwardNode) : Nil
          prefix = node.prefix
          config = forward_config(node, prefix)
          mod = load_module(node.url, node.line, node.column, config, implicit: !config.empty?)
          mod.variables.each do |name, value|
            exported = prefix ? prefix + name : name
            next unless forward_visible?(node, "$" + exported)
            @forward_variables[exported] = value
          end
          mod.mixins.each do |name, closure|
            exported = prefix ? prefix + name : name
            next unless forward_visible?(node, exported)
            @forward_mixins[exported] = closure
          end
          mod.functions.each do |name, fn|
            exported = prefix ? prefix + name : name
            next unless forward_visible?(node, exported)
            @forward_functions[exported] = fn
          end
        end

        # The importing file's globals that reach the module behind this
        # `@forward` (dart-sass `Configuration#throughForward`): only the
        # names this rule shows, with its prefix stripped so `$btn-pad`
        # configures `$pad` behind `@forward "button" as btn-*`. Empty
        # outside a classic `@import` — a `@use`d forwarding index is never
        # configured by its user's globals.
        #
        # Without this, `$btn-pad: 99px; @import "components";` — the
        # classic "set the variables, then import the library" pattern —
        # lost the override: the forwarded module was loaded unconfigured,
        # its `$btn-pad: 8px !default` took the default, and
        # `bind_imported_forwards` then wrote that default over the
        # importer's own value. dart-sass keeps 99px.
        private def forward_config(node : Ast::ForwardNode, prefix : String?) : Hash(String, String)
          config = {} of String => String
          globals = @import_config
          return config unless globals
          globals.each do |name, value|
            next if value == "null"
            next unless forward_visible?(node, "$" + name)
            if prefix
              next unless name.starts_with?(prefix) && name.size > prefix.size
              config[name[prefix.size..]] = value
            else
              config[name] = value
            end
          end
          config
        end

        private def forward_visible?(node : Ast::ForwardNode, marker_name : String) : Bool
          if shown = node.shown
            shown.includes?(marker_name)
          elsif hidden = node.hidden
            !hidden.includes?(marker_name)
          else
            true
          end
        end

        private def register_module(node : Ast::UseNode, mod : SassModule) : Nil
          case ns = node.namespace
          when "*"
            scope = @env.root
            # `as *` dumps members into the global scope, so a name already
            # bound to something else is a genuine ambiguity — silently
            # overwriting it loses whichever definition lost the race.
            # Re-registering the *same* module (the classic-@import merge
            # can reach one file from several places) rebinds identical
            # values and is not a collision.
            mod.variables.each do |name, value|
              existing = scope.variables[name]?
              if existing && existing != value
                error_at(node.line, node.column,
                  "$#{name} is defined both here and in \"#{node.url}\"")
              end
              scope.variables[name] = value
            end
            mod.mixins.each do |name, closure|
              existing = scope.mixins[name]?
              if existing && existing != closure
                error_at(node.line, node.column,
                  "mixin #{name} is defined both here and in \"#{node.url}\"")
              end
              scope.mixins[name] = closure
            end
            mod.functions.each do |name, fn|
              existing = scope.functions[name]?
              if existing && existing != fn
                error_at(node.line, node.column,
                  "function #{name} is defined both here and in \"#{node.url}\"")
              end
              scope.functions[name] = fn
            end
          else
            ns ||= default_namespace(node.url)
            unless @env.declare_module(ns, mod)
              # Re-declaring the same module under the same namespace is
              # a no-op; a different module is a collision.
              unless @env.module?(ns).same?(mod)
                error_at(node.line, node.column, "module namespace \"#{ns}\" is already taken")
              end
            end
          end
        end

        # Members whose name starts with `-` or `_` are private to their
        # module and must never cross a module boundary — that prefix is
        # the only mechanism a partial has to keep helpers off its public
        # surface. `normalize_ident` has already folded `_` to `-`.
        private def export_members(members : Hash(String, V)) : Hash(String, V) forall V
          members.reject { |name, _| name.starts_with?("-") }
        end

        private def default_namespace(url : String) : String
          return url.lchop("sass:") if url.starts_with?("sass:")
          base = File.basename(url)
          base = base.chomp(".scss").lchop("_")
          if base == "index"
            parent = File.basename(File.dirname(url))
            base = parent unless parent == "." || parent.empty?
          end
          base
        end

        private def eval_import(node : Ast::ImportNode) : Nil
          canonical, source = @importer.load(node.url, @path, @path, node.line, node.column)
          check_cycle(canonical, node.line, node.column)
          display = @importer.display_path(canonical)
          sheet = Parser.parse(source, display)

          saved_path = @path
          @path = display
          @load_stack << canonical
          # `@forward` inside the imported sheet only STAGES members as the
          # enclosing module's re-exports (`eval_forward`), so nothing landed
          # in the importer's own scope: `@import "components"` — the classic
          # spelling for a `components/_index.scss` that only `@forward`s its
          # partials — left every forwarded `$var`/mixin/function undefined.
          # dart-sass gives the importing file access to them, so diff the
          # staging maps across the import and bind what it added.
          fwd_vars_before = @forward_variables.dup
          fwd_mixins_before = @forward_mixins.dup
          fwd_fns_before = @forward_functions.dup
          saved_import_config = @import_config
          # dart-sass "implicit configuration": the importer's globals, as
          # they stand when the import runs, configure the `!default`
          # variables of every module the imported sheet `@forward`s.
          @import_config = @env.root.variables.dup
          begin
            # Classic import: evaluated inline in the current scope/sink.
            eval_nodes(sheet.children)
          ensure
            @load_stack.pop
            @path = saved_path
            @import_config = saved_import_config
          end
          bind_imported_forwards(fwd_vars_before, fwd_mixins_before, fwd_fns_before)
        end

        # Bind members newly staged by `@forward`s inside a classic `@import`
        # into the importing scope. Only additions/changes are bound, so a
        # `@forward` the importing file wrote itself (staged before this
        # import ran) is left alone.
        #
        # The CURRENT scope, not the root: a nested import (`.wrap { @import
        # "components"; }`) scopes its members to the block in dart-sass,
        # exactly as this evaluator already scopes the variables of a plain
        # nested import. Binding to the root leaked `$btn-pad` to rules
        # after the block that dart-sass rejects as undefined.
        private def bind_imported_forwards(vars_before : Hash(String, String),
                                           mixins_before : Hash(String, MixinClosure),
                                           fns_before : Hash(String, SassFn)) : Nil
          @forward_variables.each do |name, value|
            next if vars_before[name]? == value
            @env.assign_var(name, value, default: false, global: false)
          end
          @forward_mixins.each do |name, closure|
            next if mixins_before[name]? == closure
            @env.declare_mixin(name, closure)
          end
          @forward_functions.each do |name, fn|
            next if fns_before[name]? == fn
            @env.declare_function(name, fn)
          end
        end

        private def check_cycle(canonical : String, line : Int32, column : Int32) : Nil
          return unless @load_stack.includes?(canonical)
          chain = (@load_stack + [canonical]).map { |p| @importer.display_path(p) }.join(" → ")
          error_at(line, column, "circular @use/@import: #{chain}")
        end

        # ---------------------------------------------------------------
        # Template resolution
        # ---------------------------------------------------------------

        # Lenient value resolution: when the template parses as an
        # expression that actually computes (operators / known function
        # calls), evaluate it; otherwise — and on any soft failure — the
        # legacy verbatim path keeps output byte-identical.
        private def resolve_value(template : Ast::TextTemplate) : String
          # A bare `$var` propagates its storage text EXACTLY: "null" must
          # stay "null" (argument passing and `@if $x` depend on it — the
          # splicing path below elides null, which turned a null argument
          # into a truthy empty string), and structural parens of nested
          # lists must survive for later coercion.
          if template.pieces.size == 1 && (ref = template.pieces[0].as?(Ast::VarRef))
            return lookup_var_ref(ref)
          end
          if node = Expr.parse(template)
            if Expr.computes?(node, self, force_div: true)
              begin
                return value_storage(Expr::Evaluator.new(self, force_div: true).eval(node))
              rescue ex : NamespacedEvalError
                warn_namespaced(template, ex)
              rescue ex : DuplicateKeyError
                error_at(template.line, template.column, ex.message || "Duplicate key")
              rescue SoftEvalError
                # fall through to the verbatim path
              end
            end
          end
          collapse_ws(resolve_template(template, allow_vars: true))
        end

        # Declaration-value flavour of `resolve_value`: serializes as CSS
        # rather than as storage text, and reports whether the value was a
        # real null. The text can't carry that on its own — `inspect(null)`
        # legitimately yields the string "null", which must be emitted,
        # while a null-valued variable must omit the declaration.
        private def resolve_decl_value(template : Ast::TextTemplate,
                                       fold_calc : Bool = true) : ResolvedValue
          if node = Expr.parse(template)
            if Expr.computes?(node, self, fold_calc: fold_calc)
              begin
                value = Expr::Evaluator.new(self, fold_calc: fold_calc).eval(node)
                return ResolvedValue.new(value.to_css, value.is_a?(NullV))
              rescue ex : NamespacedEvalError
                warn_namespaced(template, ex)
              rescue ex : DuplicateKeyError
                error_at(template.line, template.column, ex.message || "Duplicate key")
              rescue SoftEvalError
                # fall through to the verbatim path
              end
            end
          end
          # The verbatim path only has text, where a stored null reads back
          # as "null" (see `value_storage`).
          text = collapse_ws(resolve_template(template, allow_vars: true))
          ResolvedValue.new(text, text == "null")
        end

        # Same lenient policy for `#{...}` bodies, minus the whitespace
        # collapsing (interpolation output is spliced into surrounding
        # text exactly as today when nothing computes).
        private def resolve_interp(template : Ast::TextTemplate) : String
          if node = Expr.parse(template)
            if Expr.computes?(node, self, force_div: true)
              begin
                # `interp_css`, not `to_css`: inside `#{...}` dart-sass
                # unquotes strings at every nesting level, so a list of
                # quoted strings must render `a, b`. `unquote_interp` at the
                # call site only ever handled the single-string case.
                return Expr::Evaluator.new(self, force_div: true).eval(node).interp_css
              rescue ex : NamespacedEvalError
                warn_namespaced(template, ex)
              rescue SoftEvalError
                # fall through to the verbatim path
              end
            end
          end
          unquote_list_interp(resolve_template(template, allow_vars: true))
        end

        # The verbatim path substitutes a variable's STORAGE text, which
        # keeps strings quoted — correct for a value context, wrong inside
        # `#{...}`. `#{$stack}` for `$stack: ("a", "b")` has to render
        # `a, b`; the stored `"a", "b"` produced `content: ""a", "b""`.
        # Only a text that round-trips exactly through a list is rewritten,
        # so every other verbatim substitution stays byte-identical.
        # (A lone quoted string is already handled by `unquote_interp`.)
        private def unquote_list_interp(text : String) : String
          return text unless text.includes?('"') || text.includes?('\'')
          value = Expr.coerce(text)
          return text unless value.is_a?(ListV)
          return text unless value.to_css == text
          value.interp_css
        end

        # At-rule preludes evaluate expressions only inside feature
        # values — the `(feature: VALUE)` spans of @media/@supports —
        # so `@media (min-width: map-get($bp, md))` and breakpoint
        # arithmetic work (dart-sass parity) while the query structure
        # itself stays verbatim.
        private def resolve_prelude(template : Ast::TextTemplate,
                                    fold_calc : Bool = true) : String
          segments = [] of {Bool, Ast::TextTemplate} # {is_value, sub-template}
          current = [] of Ast::Piece
          buf = String::Builder.new
          buf_size = 0
          in_value = false
          value_depth = 0
          depth = 0

          template.pieces.each do |piece|
            unless piece.is_a?(String)
              if buf_size > 0
                current << buf.to_s
                buf = String::Builder.new
                buf_size = 0
              end
              current << piece
              next
            end
            chars = piece.chars
            i = 0
            while i < chars.size
              c = chars[i]
              case c
              when '"', '\''
                quote = c
                buf << c
                buf_size += 1
                i += 1
                while i < chars.size
                  sc = chars[i]
                  buf << sc
                  buf_size += 1
                  if sc == '\\' && i + 1 < chars.size
                    i += 1
                    buf << chars[i]
                    buf_size += 1
                  elsif sc == quote
                    break
                  end
                  i += 1
                end
              when '('
                depth += 1
                buf << c
                buf_size += 1
              when ')'
                if in_value && depth == value_depth
                  # Close the value span before this paren.
                  if buf_size > 0
                    current << buf.to_s
                    buf = String::Builder.new
                    buf_size = 0
                  end
                  segments << {true, Ast::TextTemplate.new(current, template.line, template.column)}
                  current = [] of Ast::Piece
                  in_value = false
                end
                depth -= 1
                buf << c
                buf_size += 1
              when ':'
                buf << c
                buf_size += 1
                if !in_value && depth >= 1
                  # Keep the whitespace after ':' on the verbatim side so
                  # original spacing survives when nothing computes.
                  while i + 1 < chars.size && chars[i + 1].ascii_whitespace?
                    i += 1
                    buf << chars[i]
                    buf_size += 1
                  end
                  current << buf.to_s if buf_size > 0
                  buf = String::Builder.new
                  buf_size = 0
                  segments << {false, Ast::TextTemplate.new(current, template.line, template.column)}
                  current = [] of Ast::Piece
                  in_value = true
                  value_depth = depth
                end
              else
                buf << c
                buf_size += 1
              end
              i += 1
            end
          end
          current << buf.to_s if buf_size > 0
          segments << {false, Ast::TextTemplate.new(current, template.line, template.column)} unless current.empty?

          text = String.build do |io|
            segments.each do |is_value, sub|
              # Feature values render like declaration values (CSS text,
              # not storage text) — the storage spellings `(10px,)` and
              # `(a b), (c d)` must not leak into a media query.
              io << (is_value ? resolve_decl_value(sub, fold_calc: fold_calc).text : resolve_template(sub, allow_vars: true))
            end
          end
          collapse_ws(text)
        end

        # Serializes a computed value for storage in a variable or a
        # declaration. Null and the empty list keep parseable spellings
        # so they survive the string round-trip.
        private def value_storage(value : Value) : String
          value.inspect_css
        end

        # Text to emit for a declaration value, plus whether it was a real
        # null (see `resolve_decl_value`).
        private record ResolvedValue, text : String, null_value : Bool

        # ---------------------------------------------------------------
        # Expr::Host — services for expression evaluation
        # ---------------------------------------------------------------

        # :nodoc:
        def expr_var(name : String, ns : String?) : String
          if ns
            mod = @env.module?(ns)
            raise NamespacedEvalError.new("there is no module namespace \"#{ns}\"") unless mod
            mod.variables[Sass.normalize_ident(name)]? ||
              raise NamespacedEvalError.new("undefined variable: \"#{ns}.$#{name}\"")
          else
            @env.lookup_var(name) ||
              raise SoftEvalError.new("undefined variable: \"$#{name}\"")
          end
        end

        # :nodoc:
        def expr_parent_selectors : Array(String)?
          @parent_selectors
        end

        # sass:meta functions that need evaluator state (scopes, mixins,
        # @content) and therefore can't live in the static builtin tables.
        META_HOST_FNS = %w[variable-exists global-variable-exists
          function-exists mixin-exists content-exists get-function call keywords]

        # :nodoc: — see Expr::Host#expr_keywords.
        def expr_keywords(name : String, var_ns : String?, call_ns : String?) : Value?
          return if var_ns # a module variable is never an arglist
          norm = Sass.normalize_ident(name)
          # Only when the call actually resolves to the meta built-in.
          return unless host_meta_fn?(call_ns, "keywords")
          stored = @env.lookup_var(KEYWORDS_VAR_PREFIX + norm)
          unless stored
            raise SoftEvalError.new("keywords(): $#{name} is not an argument list")
          end
          @keywords_accessed << norm
          Expr.coerce(stored).as?(MapV) || MapV.new([] of MapEntry)
        end

        # :nodoc:
        def expr_call(ns : String?, name : String, args : Array(Value),
                      kwargs : Hash(String, Value)) : Value?
          norm = Sass.normalize_ident(name)
          if host_meta_fn?(ns, norm)
            begin
              return call_meta_host_fn(norm, args, kwargs)
            rescue ex : NamespacedEvalError
              raise ex
            rescue ex : SoftEvalError
              # Same policy as every other namespaced builtin: a failure
              # inside `meta.…` must not fall back to verbatim CSS.
              raise NamespacedEvalError.new(ex.message || "call failed") if ns
              raise ex
            end
          end
          if ns
            mod = @env.module?(ns)
            raise NamespacedEvalError.new("there is no module namespace \"#{ns}\"") unless mod
            fn = mod.functions[norm]? ||
                 raise NamespacedEvalError.new("undefined function: \"#{ns}.#{name}\"")
            begin
              invoke_fn(fn, name, args, kwargs)
            rescue ex : NamespacedEvalError
              raise ex
            rescue ex : SoftEvalError
              # A failure *inside* a namespaced built-in (`math.div(1px, 0)`,
              # `math.percentage(1px)`, …) must not fall back either — the
              # fallback emits `math.div(1px, 0)` as a CSS value.
              raise NamespacedEvalError.new(ex.message || "call failed")
            end
          elsif fn = @env.lookup_function(norm)
            invoke_fn(fn, name, args, kwargs)
          elsif builtin = Builtins::GLOBAL_FNS[norm]?
            builtin.call(args, kwargs)
          end
        rescue ShapeMismatch
          # A CSS-shadowing built-in declining this call shape. Answering
          # nil reconstructs just this call as verbatim CSS and leaves the
          # rest of the declaration evaluating normally.
          nil
        end

        private def invoke_fn(fn : SassFn, name : String, args : Array(Value),
                              kwargs : Hash(String, Value)) : Value
          case fn
          in FunctionClosure
            call_user_function(fn, name, args, kwargs)
          in Builtins::Fn
            fn.call(args, kwargs)
          end
        end

        # :nodoc:
        def expr_known_fn?(ns : String?, name : String) : Bool
          # Namespaced calls always count as computing — a missing module
          # or function then soft-fails (lenient: verbatim, strict: loud).
          return true if ns
          norm = Sass.normalize_ident(name)
          !@env.lookup_function(norm).nil? || Builtins::GLOBAL_FNS.has_key?(norm) ||
            META_HOST_FNS.includes?(norm)
        end

        # True when this call resolves to a host-backed sass:meta function:
        # the legacy global spelling (unless shadowed by a user @function)
        # or a namespaced call whose namespace is the built-in meta module.
        private def host_meta_fn?(ns : String?, norm : String) : Bool
          return false unless META_HOST_FNS.includes?(norm)
          if ns
            mod = @env.module?(ns)
            !mod.nil? && mod.same?(BUILTIN_MODULES["meta"]?)
          else
            @env.lookup_function(norm).nil?
          end
        end

        private def call_meta_host_fn(norm : String, args : Array(Value),
                                      kwargs : Hash(String, Value)) : Value
          case norm
          when "content-exists"
            unless args.empty? && kwargs.empty?
              raise SoftEvalError.new("content-exists() takes no arguments")
            end
            return BoolV.new(!@content.nil?)
          when "get-function"
            return meta_get_function(args, kwargs)
          when "call"
            return meta_call(args, kwargs)
          when "keywords"
            # The VarE fast path in Expr's eval_call handles the real
            # `keywords($args)` shape; anything else isn't an arglist.
            raise SoftEvalError.new("keywords() expects an argument-list variable ($args)")
          end
          raise SoftEvalError.new("#{norm}() takes one argument, $name") unless args.size <= 1
          kwargs.each_key do |key|
            next if key == "name"
            next if key == "module" && norm != "variable-exists"
            raise SoftEvalError.new("#{norm}(): no parameter named $#{key}")
          end
          value = args[0]? || kwargs["name"]?
          member =
            case value
            when Str then value.text
            when Raw then value.text
            else
              raise SoftEvalError.new("#{norm}() expects a string, got #{value.try(&.to_css).inspect}")
            end
          member = Sass.normalize_ident(member.lchop('$'))
          if mod_arg = kwargs["module"]?
            mod = @env.module?(module_arg_text(mod_arg))
            raise SoftEvalError.new("#{norm}(): no module named #{mod_arg.to_css.inspect}") unless mod
            exists =
              case norm
              when "global-variable-exists" then mod.variables.has_key?(member)
              when "function-exists"        then mod.functions.has_key?(member)
              else # mixin-exists
                mod.mixins.has_key?(member)
              end
            return BoolV.new(exists)
          end
          exists =
            case norm
            when "variable-exists"
              !@env.lookup_var(member).nil?
            when "global-variable-exists"
              @env.root.variables.has_key?(member)
            when "function-exists"
              !named_function(member).nil?
            else # mixin-exists
              !@env.lookup_mixin(member).nil?
            end
          BoolV.new(exists)
        end

        # Resolves a function name the way a call site would: user
        # @functions win, then the host-backed meta functions (wrapped so
        # they are first-class values for get-function/call), then the
        # global builtins.
        private def named_function(norm : String) : SassFn?
          if fn = @env.lookup_function(norm)
            return fn
          end
          if META_HOST_FNS.includes?(norm)
            return Builtins::Fn.new { |a, k| call_meta_host_fn(norm, a, k) }
          end
          Builtins::GLOBAL_FNS[norm]?
        end

        private def meta_get_function(args : Array(Value), kwargs : Hash(String, Value)) : Value
          if kwargs["css"]?.try(&.truthy?)
            raise SoftEvalError.new("get-function($css: true) is not supported")
          end
          value = args[0]? || kwargs["name"]?
          name =
            case value
            when Str then value.text
            when Raw then value.text
            else
              raise SoftEvalError.new("get-function() expects a function name string")
            end
          norm = Sass.normalize_ident(name)
          fn = if mod_name = kwargs["module"]?
                 mod = @env.module?(module_arg_text(mod_name))
                 raise SoftEvalError.new("get-function(): no module named #{mod_name.to_css.inspect}") unless mod
                 mod.functions[norm]?
               else
                 named_function(norm)
               end
          raise SoftEvalError.new("get-function(): no function named #{name.inspect}") unless fn
          FnRefV.new(norm, fn)
        end

        private def module_arg_text(value : Value) : String
          value.is_a?(Str) ? value.text : value.to_css
        end

        private def meta_call(args : Array(Value), kwargs : Hash(String, Value)) : Value
          ref = args[0]?
          raise SoftEvalError.new("call() expects a function reference") unless ref
          rest = args[1..]
          name =
            case ref
            when FnRefV
              return invoke_fn(ref.fn, ref.name, rest, kwargs)
            when Str
              # Legacy spelling: call("name", args...).
              ref.text
            when Raw
              # A reference that round-tripped through string storage
              # degrades to its `get-function("name")` spelling
              # (`$f: get-function("darken"); call($f, …)`) — re-resolve
              # it by name.
              match = ref.text.match(/\Aget-function\(\s*"([^"]*)"\s*\)\z/)
              raise SoftEvalError.new("call() expects a function reference, got #{ref.to_css.inspect}") unless match
              match[1]
            else
              raise SoftEvalError.new("call() expects a function reference, got #{ref.to_css.inspect}")
            end
          norm = Sass.normalize_ident(name)
          fn = named_function(norm)
          raise SoftEvalError.new("call(): no function named #{name.inspect}") unless fn
          invoke_fn(fn, norm, rest, kwargs)
        end

        # :nodoc:
        def expr_interp(template : Ast::TextTemplate) : String
          unquote_interp(resolve_interp(template))
        end

        private def resolve_template(template : Ast::TextTemplate, allow_vars : Bool) : String
          pieces = template.pieces
          String.build do |io|
            pieces.each_with_index do |piece, idx|
              case piece
              in String
                io << piece
              in Ast::VarRef
                unless allow_vars
                  error_at(piece.line, piece.column,
                    "variables aren't allowed here (use \#{#{piece.lexeme}} interpolation)")
                end
                if keyword_label?(pieces, idx)
                  io << piece.lexeme
                else
                  # A null variable substitutes as nothing. Storage spells
                  # it "null" (see `value_storage`), and that spelling must
                  # not leak into a selector or value as literal text — the
                  # optional-modifier idiom `.btn#{$mod}` with `$mod: null`
                  # has to yield `.btn`, not `.btnnull`.
                  var_text = lookup_var_ref(piece)
                  io << var_display_text(var_text) unless var_text == "null"
                end
              in Ast::Interp
                io << unquote_interp(resolve_interp(piece.inner))
              end
            end
          end
        end

        # True when this `$name` is a keyword-argument label (`f($x: 1)`)
        # rather than a variable reference. The typed path binds it as a
        # kwarg; when that path declines — unknown function, or a builtin
        # that doesn't take keyword arguments — the verbatim fallback has
        # to reproduce the label as written. Substituting instead either
        # emits garbage (`str-slice("ab", 99: 2)` when a variable of that
        # name happens to exist) or raises a bogus "undefined variable"
        # for a name the author never used as a variable.
        private def keyword_label?(pieces : Array(Ast::Piece), idx : Int32) : Bool
          nxt = pieces[idx + 1]?
          nxt.is_a?(String) && nxt.lstrip.starts_with?(':')
        end

        # dart-sass semantics: `#{...}` substitutes the UNQUOTED value of a
        # string — `$q: "x"` interpolates as `x`, never `"x"` (a quoted
        # substitution terminates the surrounding string early and ships
        # invalid CSS, e.g. `content: "say "x""`). Only a result that is one
        # complete quoted string unquotes; anything else — already unquoted,
        # or multiple tokens like `"a" "b"` — passes through verbatim.
        private def unquote_interp(text : String) : String
          return text if text.size < 2
          quote = text[0]
          return text unless quote == '"' || quote == '\''
          return text unless text[-1] == quote
          inner = text[1..-2]
          i = 0
          while i < inner.size
            c = inner[i]
            if c == '\\'
              i += 2
              next
            end
            # An unescaped same-quote char inside means this is not ONE
            # quoted string ("a" + "b" territory) — leave it alone.
            return text if c == quote
            i += 1
          end
          inner
        end

        # Storage text is `inspect_css` — nested unbracketed lists carry
        # structural parens (`(inset 0 1px #fff), (0 1px #000)`) and a
        # single-element comma list spells itself `(10px,)` so they
        # survive the string round-trip. Those spellings are NOT valid
        # CSS, so a verbatim `$var` substitution must render such values
        # with `to_css` instead. Every other storage text (including
        # verbatim never-computed source) passes through untouched, which
        # is what keeps plain-CSS output byte-identical.
        private def var_display_text(storage : String) : String
          return storage unless storage.includes?('(')
          value = Expr.coerce(storage)
          if value.is_a?(ListV) &&
             (value.items.any? { |i| i.is_a?(ListV) && !i.bracketed } ||
             (value.sep == ListV::Sep::Comma && value.items.size == 1))
            value.to_css
          else
            storage
          end
        end

        private def lookup_var_ref(ref : Ast::VarRef) : String
          if ns = ref.namespace
            mod = @env.module?(ns)
            error_at(ref.line, ref.column, "there is no module namespace \"#{ns}\"") unless mod
            mod.variables[Sass.normalize_ident(ref.name)]? ||
              error_at(ref.line, ref.column, "undefined variable: \"#{ns}.$#{ref.name}\"")
          else
            @env.lookup_var(ref.name) ||
              error_at(ref.line, ref.column, "undefined variable: \"$#{ref.name}\"")
          end
        end

        # Collapses whitespace runs to single spaces outside quoted
        # strings and trims the ends.
        private def collapse_ws(text : String) : String
          chars = text.chars
          result = String.build do |io|
            emitted = false
            pending = false
            i = 0
            while i < chars.size
              c = chars[i]
              if c == '"' || c == '\''
                io << ' ' if pending && emitted
                pending = false
                quote = c
                io << c
                i += 1
                while i < chars.size
                  sc = chars[i]
                  io << sc
                  if sc == '\\' && i + 1 < chars.size
                    i += 1
                    io << chars[i]
                  elsif sc == quote
                    break
                  end
                  i += 1
                end
                emitted = true
              elsif c.ascii_whitespace?
                pending = true
              else
                io << ' ' if pending && emitted
                pending = false
                io << c
                emitted = true
              end
              i += 1
            end
          end
          result
        end

        private def error_at(line : Int32, column : Int32, message : String) : NoReturn
          raise SyntaxError.new(message, @path, line, column)
        end

        # One tick of the shared loop budget (see MAX_LOOP_ITERATIONS).
        private def count_loop_iteration(line : Int32, column : Int32) : Nil
          @loop_iterations += 1
          return if @loop_iterations <= MAX_LOOP_ITERATIONS
          error_at(line, column,
            "stylesheet exceeded #{MAX_LOOP_ITERATIONS} total @for/@each/@while iterations " \
            "(runaway loop bounds?)")
        end

        # A namespaced reference that fails still takes the documented lenient
        # fallback (see the `math.div` passthrough spec), but the fallback
        # splices `math.div(1px, 0)` into the stylesheet — and no CSS function
        # name may contain a `.`, so that declaration is dead on arrival in
        # every browser. Leniency exists to preserve *valid* CSS the compiler
        # doesn't model (`-webkit-…()`, `progid:…`), which is never namespaced,
        # so this particular fallback is always a silent breakage: say so.
        private def warn_namespaced(template : Ast::TextTemplate, ex : NamespacedEvalError) : Nil
          Logger.warn "Sass: #{@path}:#{template.line}:#{template.column}: " \
                      "#{ex.message} — emitted as literal text, which is not valid CSS."
        end
      end
    end
  end
end
