# Evaluator: SCSS AST → flat CSS tree.
#
# Handles variable scoping, selector nesting and `&` resolution,
# conditional at-rule bubbling (@media/@supports inside rules), mixin
# expansion with @content, and @use/@import module loading. Values are
# verbatim strings after substitution; unknown functions (calc, var,
# rgba, ...) pass through untouched — that property is what makes valid
# plain CSS compile to itself.
#
# Extension seams for the full language: `eval_node`'s dispatch gains
# arms for @if/@each/@for nodes; richer value types and a function
# registry slot into the template-resolution path.

require "./ast"
require "./environment"
require "./css"
require "./importer"
require "./parser"

module Hwaro
  module Assets
    module Sass
      class Evaluator
        MAX_INCLUDE_DEPTH = 100

        # A `{ ... }` block passed to `@include`; evaluated at `@content`
        # with the caller's variable scope (dart-sass lexical semantics).
        # :nodoc:
        class ContentBlock
          getter nodes : Array(Ast::Node)
          getter env : Environment
          getter outer : ContentBlock?
          getter path : String

          def initialize(@nodes, @env, @outer, @path)
          end
        end

        @env : Environment
        @sink : Array(Css::Node)
        @current_rule : Css::Rule?
        @current_at : Css::AtRule?
        @parent_selectors : Array(String)?
        @content : ContentBlock?
        @in_keyframes : Bool
        @include_depth : Int32
        @path : String

        def initialize(@importer : Importer, path : String)
          @env = Environment.new
          @sink = [] of Css::Node
          @current_rule = nil
          @current_at = nil
          @parent_selectors = nil
          @content = nil
          @in_keyframes = false
          @include_depth = 0
          @path = path
          @loaded_modules = {} of String => SassModule
          @load_stack = [] of String
          @module_css = [] of Css::Node
        end

        # Registers the entry file's canonical path so a self-import cycle
        # is caught at the first hop.
        def seed_load_stack(canonical : String) : Nil
          @load_stack << canonical
        end

        def evaluate(sheet : Ast::Stylesheet) : Array(Css::Node)
          eval_nodes(sheet.children)
          @module_css + @sink
        end

        private def eval_nodes(nodes : Array(Ast::Node)) : Nil
          nodes.each { |node| eval_node(node) }
        end

        private def eval_node(node : Ast::Node) : Nil
          case node
          when Ast::VarDeclNode
            @env.assign_var(node.name, resolve_value(node.value), node.default, node.global)
          when Ast::MixinDefNode
            @env.declare_mixin(node.name, MixinClosure.new(node, @env, @path))
          when Ast::RuleNode
            eval_rule(node)
          when Ast::DeclarationNode
            eval_declaration(node)
          when Ast::IncludeNode
            eval_include(node)
          when Ast::ContentNode
            eval_content
          when Ast::UseNode
            eval_use(node)
          when Ast::ImportNode
            eval_import(node)
          when Ast::RawAtRuleNode
            eval_at_rule(node)
          when Ast::CommentNode
            emit_comment(node.text)
          end
        end

        # ---------------------------------------------------------------
        # Rules & declarations
        # ---------------------------------------------------------------

        private def eval_rule(node : Ast::RuleNode) : Nil
          text = resolve_template(node.selector, allow_vars: false)
          parts = Parser.split_top_level_commas(text).map { |s| collapse_ws(s) }.reject(&.empty?)
          error_at(node.line, node.column, "expected selector") if parts.empty?

          selectors = @in_keyframes ? parts : combine_selectors(parts, node)
          rule = Css::Rule.new(selectors)
          @sink << rule

          saved_rule = @current_rule
          saved_parents = @parent_selectors
          saved_env = @env
          @current_rule = rule
          @parent_selectors = selectors
          @env = Environment.new(saved_env) # each block is a variable scope
          eval_nodes(node.children)
          @current_rule = saved_rule
          @parent_selectors = saved_parents
          @env = saved_env
        end

        private def combine_selectors(parts : Array(String), node : Ast::RuleNode) : Array(String)
          parents = @parent_selectors
          result = [] of String
          parts.each do |part|
            has_amp = contains_parent_ref?(part)
            if parents.nil?
              if has_amp
                error_at(node.line, node.column, "top-level selectors may not contain \"&\"")
              end
              result << part
            elsif has_amp
              parents.each do |parent|
                result << substitute_parent(part, parent)
              end
            else
              parents.each { |parent| result << "#{parent} #{part}" }
            end
          end
          result
        end

        # True when the selector contains a `&` outside quoted strings and
        # attribute brackets — a scan-only twin of substitute_parent.
        private def contains_parent_ref?(selector : String) : Bool
          chars = selector.chars
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
              return true
            end
            i += 1
          end
          false
        end

        # Replaces top-level `&` with the parent selector; `&` inside
        # quoted strings and attribute brackets is literal.
        private def substitute_parent(selector : String, replacement : String) : String
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
                io << replacement
              else
                io << c
              end
              i += 1
            end
          end
        end

        private def eval_declaration(node : Ast::DeclarationNode) : Nil
          name = collapse_ws(resolve_template(node.name, allow_vars: false))
          value =
            if node.custom_property
              resolve_template(node.value, allow_vars: true).strip
            else
              resolve_value(node.value)
            end
          decl = Css::Decl.new(name, value, node.important)
          if rule = @current_rule
            rule.items << decl
          elsif at = @current_at
            at.items << decl
          else
            error_at(node.line, node.column, "declarations may only appear within style rules")
          end
        end

        private def emit_comment(text : String) : Nil
          if rule = @current_rule
            rule.items << Css::Comment.new(text)
          elsif at = @current_at
            at.items << Css::Comment.new(text)
          else
            @sink << Css::Comment.new(text)
          end
        end

        # ---------------------------------------------------------------
        # At-rules
        # ---------------------------------------------------------------

        private def eval_at_rule(node : Ast::RawAtRuleNode) : Nil
          prelude = collapse_ws(resolve_template(node.prelude, allow_vars: true))

          children = node.children
          unless children
            text = prelude.empty? ? "@#{node.name};" : "@#{node.name} #{prelude};"
            @sink << Css::Raw.new(text)
            return
          end

          at = Css::AtRule.new(node.name, prelude)
          @sink << at

          saved_sink = @sink
          saved_rule = @current_rule
          saved_at = @current_at
          saved_parents = @parent_selectors
          saved_keyframes = @in_keyframes
          saved_env = @env

          @sink = at.children
          @current_at = at
          @env = Environment.new(saved_env)
          if keyframes?(node.name)
            @current_rule = nil
            @parent_selectors = nil
            @in_keyframes = true
          elsif (rule = saved_rule) && conditional_group?(node.name)
            # Conditional at-rule nested in a style rule: bubble the
            # at-rule out and re-wrap the declarations in the rule's
            # selector (`.a { @media (x) { color } }` →
            # `@media (x) { .a { color } }`). Descriptor at-rules
            # (@font-face, @page, @property, ...) never take a selector
            # wrapper — their declarations belong to the at-rule itself.
            synthetic = Css::Rule.new(rule.selectors)
            at.children << synthetic
            @current_rule = synthetic
          else
            @current_rule = nil
          end

          eval_nodes(children)

          @sink = saved_sink
          @current_rule = saved_rule
          @current_at = saved_at
          @parent_selectors = saved_parents
          @in_keyframes = saved_keyframes
          @env = saved_env
        end

        private def keyframes?(name : String) : Bool
          name == "keyframes" || name.ends_with?("-keyframes")
        end

        # Grouping at-rules whose bodies contain style rules — these get a
        # synthetic selector wrapper when bubbled out of a rule.
        CONDITIONAL_GROUP_AT_RULES = %w[media supports container layer document scope]

        private def conditional_group?(name : String) : Bool
          CONDITIONAL_GROUP_AT_RULES.includes?(name)
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
          bind_arguments(node, closure, call_env)

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
              ContentBlock.new(body, @env, @content, @path)
            end

          saved_env = @env
          saved_content = @content
          saved_path = @path
          @env = call_env
          @content = content
          @path = closure.path
          begin
            eval_nodes(closure.node.body)
          ensure
            @env = saved_env
            @content = saved_content
            @path = saved_path
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

        private def bind_arguments(node : Ast::IncludeNode, closure : MixinClosure, call_env : Environment) : Nil
          params = closure.node.params
          param_names = params.map { |p| Sass.normalize_ident(p.name) }
          positional = [] of String
          kwargs = {} of String => String

          node.args.each do |arg|
            value = resolve_value(arg.value) # evaluated in the caller's scope
            if name = arg.name
              name = Sass.normalize_ident(name)
              unless param_names.includes?(name)
                error_at(node.line, node.column, "no parameter named $#{name} in mixin #{node.name}")
              end
              if kwargs.has_key?(name)
                error_at(node.line, node.column, "duplicate argument $#{name}")
              end
              kwargs[name] = value
            else
              unless kwargs.empty?
                error_at(node.line, node.column, "positional arguments must precede keyword arguments")
              end
              positional << value
            end
          end

          if positional.size > params.size
            error_at(node.line, node.column,
              "mixin #{node.name} takes #{params.size} argument(s) but #{positional.size} were passed")
          end

          params.each_with_index do |param, i|
            param_name = param_names[i]
            value =
              if i < positional.size
                if kwargs.has_key?(param_name)
                  error_at(node.line, node.column, "$#{param.name} was passed both by position and by name")
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
                error_at(node.line, node.column, "missing argument $#{param.name} for mixin #{node.name}")
              end
            call_env.variables[param_name] = value
          end
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
            else
              false
            end
          end
        end

        private def eval_content : Nil
          block = @content
          return unless block # @include without a body: @content emits nothing

          saved_env = @env
          saved_content = @content
          saved_path = @path
          @env = Environment.new(block.env)
          @content = block.outer
          @path = block.path
          begin
            eval_nodes(block.nodes)
          ensure
            @env = saved_env
            @content = saved_content
            @path = saved_path
          end
        end

        # ---------------------------------------------------------------
        # @use / @import
        # ---------------------------------------------------------------

        private def eval_use(node : Ast::UseNode) : Nil
          canonical, source = @importer.load(node.url, @path, @path, node.line, node.column)

          mod = @loaded_modules[canonical]?
          unless mod
            check_cycle(canonical, node.line, node.column)
            display = @importer.display_path(canonical)
            sheet = Parser.parse(source, display)

            saved_env = @env
            saved_sink = @sink
            saved_rule = @current_rule
            saved_at = @current_at
            saved_parents = @parent_selectors
            saved_content = @content
            saved_keyframes = @in_keyframes
            saved_path = @path

            module_env = Environment.new
            module_sink = [] of Css::Node
            @env = module_env
            @sink = module_sink
            @current_rule = nil
            @current_at = nil
            @parent_selectors = nil
            @content = nil
            @in_keyframes = false
            @path = display
            @load_stack << canonical
            begin
              eval_nodes(sheet.children)
            ensure
              @load_stack.pop
              @env = saved_env
              @sink = saved_sink
              @current_rule = saved_rule
              @current_at = saved_at
              @parent_selectors = saved_parents
              @content = saved_content
              @in_keyframes = saved_keyframes
              @path = saved_path
            end

            mod = SassModule.new(module_env.variables, module_env.mixins)
            @loaded_modules[canonical] = mod
            # A module's CSS is emitted once, before the code that uses it.
            @module_css.concat(module_sink)
          end

          register_module(node, mod)
        end

        private def register_module(node : Ast::UseNode, mod : SassModule) : Nil
          case ns = node.namespace
          when "*"
            scope = @env.root
            mod.variables.each { |name, value| scope.variables[name] = value }
            mod.mixins.each { |name, closure| scope.mixins[name] = closure }
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

        private def default_namespace(url : String) : String
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
          begin
            # Classic import: evaluated inline in the current scope/sink.
            eval_nodes(sheet.children)
          ensure
            @load_stack.pop
            @path = saved_path
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

        private def resolve_value(template : Ast::TextTemplate) : String
          collapse_ws(resolve_template(template, allow_vars: true))
        end

        private def resolve_template(template : Ast::TextTemplate, allow_vars : Bool) : String
          String.build do |io|
            template.pieces.each do |piece|
              case piece
              in String
                io << piece
              in Ast::VarRef
                unless allow_vars
                  error_at(piece.line, piece.column,
                    "variables aren't allowed here (use \#{#{piece.lexeme}} interpolation)")
                end
                io << lookup_var_ref(piece)
              in Ast::Interp
                io << unquote_interp(resolve_template(piece.inner, allow_vars: true))
              end
            end
          end
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
      end
    end
  end
end
