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

        # Unwinds a @function body at @return. :nodoc:
        class ReturnSignal < Exception
          getter value : Value

          def initialize(@value)
            super("@return")
          end
        end

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
          @in_function = false
          @call_depth = 0
          @forward_variables = {} of String => String
          @forward_mixins = {} of String => MixinClosure
          @forward_functions = {} of String => SassFn
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
            eval_rule(node)
          when Ast::DeclarationNode
            eval_declaration(node)
          when Ast::IncludeNode
            eval_include(node)
          when Ast::ContentNode
            eval_content
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
          when Ast::UseNode
            eval_use(node)
          when Ast::ImportNode
            eval_import(node)
          when Ast::ForwardNode
            eval_forward(node)
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
          # A null (or computed-empty) value omits the declaration
          # (dart-sass semantics). Custom properties stay verbatim.
          if !node.custom_property && (value == "null" || value.empty?) && !node.important
            return
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
          prelude = resolve_prelude(node.prelude)

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
          positional, kwargs = collect_args(node.args, "mixin #{node.name}", node.line, node.column)
          bind_params(closure.node.params, positional, kwargs, call_env,
            "mixin #{node.name}", node.line, node.column)

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

        # Resolves call-site arguments (in the caller's scope) into
        # positional strings and keyword strings; `$value...` spreads
        # lists into positionals and maps into keywords.
        private def collect_args(args : Array(Ast::Arg), what : String,
                                 line : Int32, column : Int32) : {Array(String), Hash(String, String)}
          positional = [] of String
          kwargs = {} of String => String

          args.each do |arg|
            value = resolve_value(arg.value) # evaluated in the caller's scope
            if arg.spread
              spread_into(value, positional, kwargs, line, column)
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
          {positional, kwargs}
        end

        private def spread_into(value : String, positional : Array(String),
                                kwargs : Hash(String, String), line : Int32, column : Int32) : Nil
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
          when ListV
            unless kwargs.empty?
              error_at(line, column, "positional arguments must precede keyword arguments")
            end
            spread.items.each { |item| positional << value_storage(item) }
          else
            unless kwargs.empty?
              error_at(line, column, "positional arguments must precede keyword arguments")
            end
            positional << value
          end
        end

        # Binds arguments to parameters (shared by mixins and functions).
        # `soft: true` raises SoftEvalError instead of located errors —
        # function calls happen inside expression evaluation, where
        # lenient contexts fall back and strict contexts add locations.
        private def bind_params(params : Array(Ast::Param), positional : Array(String),
                                kwargs : Hash(String, String), call_env : Environment,
                                what : String, line : Int32, column : Int32,
                                soft : Bool = false) : Nil
          param_names = params.map { |p| Sass.normalize_ident(p.name) }
          variadic = params.last?.try(&.variadic) || false
          fixed = variadic ? params.size - 1 : params.size

          kwargs.each_key do |name|
            unless param_names.includes?(name)
              bind_error("no parameter named $#{name} in #{what}", soft, line, column)
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
              call_env.variables[param_name] = rest.empty? ? "()" : rest.join(", ")
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
        end

        private def bind_error(message : String, soft : Bool, line : Int32, column : Int32) : NoReturn
          raise SoftEvalError.new(message) if soft
          error_at(line, column, message)
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
              error_at(node.line, node.column, "@each may not iterate over null")
            else
              [value]
            end
          items.each do |item|
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
          value = Expr::Evaluator.new(self, strict: true).eval(Expr.parse!(template))
          value.is_a?(Str) ? value.text : Builtins.inspect_value(value)
        rescue SoftEvalError
          resolve_value(template)
        end

        # `@at-root` re-evaluates its body outside style-rule nesting but
        # inside any surrounding at-rule (the flat sink makes that the
        # natural behavior).
        private def eval_at_root(node : Ast::AtRootNode) : Nil
          saved_rule = @current_rule
          saved_parents = @parent_selectors
          @current_rule = nil
          @parent_selectors = nil
          begin
            if selector = node.selector
              eval_rule(Ast::RuleNode.new(selector, node.children, node.line, node.column))
            else
              scoped { eval_nodes(node.children) }
            end
          ensure
            @current_rule = saved_rule
            @parent_selectors = saved_parents
          end
        end

        # ---------------------------------------------------------------
        # Functions
        # ---------------------------------------------------------------

        # Strict expression evaluation for control-flow contexts: every
        # failure is a located error.
        private def eval_expr!(template : Ast::TextTemplate) : Value
          node = Expr.parse!(template)
          Expr::Evaluator.new(self, strict: true).eval(node)
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
            bind_params(closure.node.params, positional, kw, call_env,
              "function #{name}", closure.node.line, closure.node.column, soft: true)

            saved_env = @env
            saved_path = @path
            saved_in_function = @in_function
            @env = call_env
            @path = closure.path
            @in_function = true
            begin
              eval_nodes(closure.node.body)
              raise SoftEvalError.new("function #{name} finished without @return")
            rescue ex : ReturnSignal
              ex.value
            ensure
              @env = saved_env
              @path = saved_path
              @in_function = saved_in_function
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
        private def load_module(url : String, line : Int32, column : Int32,
                                config : Hash(String, String)) : SassModule
          if url.starts_with?("sass:")
            name = url.lchop("sass:")
            mod = BUILTIN_MODULES[name]?
            error_at(line, column, "unknown built-in module \"sass:#{name}\"") unless mod
            error_at(line, column, "built-in modules can't be configured") unless config.empty?
            return mod
          end

          canonical, source = @importer.load(url, @path, @path, line, column)
          if mod = @loaded_modules[canonical]?
            unless config.empty?
              error_at(line, column,
                "#{@importer.display_path(canonical)} was already loaded and can't be configured a second time")
            end
            return mod
          end

          check_cycle(canonical, line, column)
          display = @importer.display_path(canonical)
          sheet = Parser.parse(source, display)
          validate_configurable(sheet, config, url, line, column) unless config.empty?

          saved_env = @env
          saved_sink = @sink
          saved_rule = @current_rule
          saved_at = @current_at
          saved_parents = @parent_selectors
          saved_content = @content
          saved_keyframes = @in_keyframes
          saved_path = @path
          saved_fwd_vars = @forward_variables
          saved_fwd_mixins = @forward_mixins
          saved_fwd_fns = @forward_functions

          module_env = Environment.new
          config.each { |name, value| module_env.variables[name] = value }
          module_sink = [] of Css::Node
          @env = module_env
          @sink = module_sink
          @current_rule = nil
          @current_at = nil
          @parent_selectors = nil
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
              @forward_variables.merge(module_env.variables),
              @forward_mixins.merge(module_env.mixins),
              @forward_functions.merge(module_env.functions))
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
            @forward_variables = saved_fwd_vars
            @forward_mixins = saved_fwd_mixins
            @forward_functions = saved_fwd_fns
          end

          @loaded_modules[canonical] = mod
          # A module's CSS is emitted once, before the code that uses it.
          @module_css.concat(module_sink)
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
          mod = load_module(node.url, node.line, node.column, {} of String => String)
          prefix = node.prefix
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
            mod.variables.each { |name, value| scope.variables[name] = value }
            mod.mixins.each { |name, closure| scope.mixins[name] = closure }
            mod.functions.each { |name, fn| scope.functions[name] = fn }
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

        # Lenient value resolution: when the template parses as an
        # expression that actually computes (operators / known function
        # calls), evaluate it; otherwise — and on any soft failure — the
        # legacy verbatim path keeps output byte-identical.
        private def resolve_value(template : Ast::TextTemplate) : String
          if node = Expr.parse(template)
            if Expr.computes?(node, self)
              begin
                return value_storage(Expr::Evaluator.new(self).eval(node))
              rescue SoftEvalError
                # fall through to the verbatim path
              end
            end
          end
          collapse_ws(resolve_template(template, allow_vars: true))
        end

        # Same lenient policy for `#{...}` bodies, minus the whitespace
        # collapsing (interpolation output is spliced into surrounding
        # text exactly as today when nothing computes).
        private def resolve_interp(template : Ast::TextTemplate) : String
          if node = Expr.parse(template)
            if Expr.computes?(node, self)
              begin
                return Expr::Evaluator.new(self).eval(node).to_css
              rescue SoftEvalError
                # fall through to the verbatim path
              end
            end
          end
          resolve_template(template, allow_vars: true)
        end

        # At-rule preludes evaluate expressions only inside feature
        # values — the `(feature: VALUE)` spans of @media/@supports —
        # so `@media (min-width: map-get($bp, md))` and breakpoint
        # arithmetic work (dart-sass parity) while the query structure
        # itself stays verbatim.
        private def resolve_prelude(template : Ast::TextTemplate) : String
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
              io << (is_value ? resolve_value(sub) : resolve_template(sub, allow_vars: true))
            end
          end
          collapse_ws(text)
        end

        # Serializes a computed value for storage in a variable or a
        # declaration. Null and the empty list keep parseable spellings
        # so they survive the string round-trip.
        private def value_storage(value : Value) : String
          case value
          when NullV
            "null"
          when ListV
            value.items.empty? ? "()" : value.to_css
          else
            value.to_css
          end
        end

        # ---------------------------------------------------------------
        # Expr::Host — services for expression evaluation
        # ---------------------------------------------------------------

        # :nodoc:
        def expr_var(name : String, ns : String?) : String
          if ns
            mod = @env.module?(ns)
            raise SoftEvalError.new("there is no module namespace \"#{ns}\"") unless mod
            mod.variables[Sass.normalize_ident(name)]? ||
              raise SoftEvalError.new("undefined variable: \"#{ns}.$#{name}\"")
          else
            @env.lookup_var(name) ||
              raise SoftEvalError.new("undefined variable: \"$#{name}\"")
          end
        end

        # :nodoc:
        def expr_call(ns : String?, name : String, args : Array(Value),
                      kwargs : Hash(String, Value)) : Value?
          norm = Sass.normalize_ident(name)
          if ns
            mod = @env.module?(ns)
            raise SoftEvalError.new("there is no module namespace \"#{ns}\"") unless mod
            fn = mod.functions[norm]? ||
                 raise SoftEvalError.new("undefined function: \"#{ns}.#{name}\"")
            invoke_fn(fn, name, args, kwargs)
          elsif fn = @env.lookup_function(norm)
            invoke_fn(fn, name, args, kwargs)
          elsif builtin = Builtins::GLOBAL_FNS[norm]?
            builtin.call(args, kwargs)
          end
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
          !@env.lookup_function(norm).nil? || Builtins::GLOBAL_FNS.has_key?(norm)
        end

        # :nodoc:
        def expr_interp(template : Ast::TextTemplate) : String
          unquote_interp(resolve_interp(template))
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
                io << unquote_interp(resolve_interp(piece.inner))
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
