# Lexical scoping for the SCSS evaluator.
#
# Values are plain Strings in the v1 subset (verbatim CSS text after
# variable/interpolation substitution). When SassScript arithmetic lands,
# a Value hierarchy (Number/Color/Bool/List) replaces the String alias —
# the Environment API is already shaped for it.

require "./ast"
require "./functions"

module Hwaro
  module Assets
    module Sass
      # Sass treats `-` and `_` as interchangeable in identifiers
      # (variables, mixins, namespaces — not selectors). All identifier
      # storage and lookup normalizes to the hyphen form so
      # `$brand-color` and `$brand_color` resolve to the same variable.
      def self.normalize_ident(name : String) : String
        name.tr("_", "-")
      end

      # Mixins close over their definition environment (dart-sass
      # semantics); `path` keeps error locations pointing at the file the
      # mixin was defined in, not the include site.
      record MixinClosure, node : Ast::MixinDefNode, env : Environment, path : String

      # User-defined @function closures, same shape as mixins.
      record FunctionClosure, node : Ast::FunctionDefNode, env : Environment, path : String

      # A callable function: a user closure or a built-in proc.
      alias SassFn = FunctionClosure | Builtins::Fn

      # A loaded `@use` module: its root-scope members (plus anything it
      # `@forward`s). Module-private state stays in the closed-over
      # environments.
      class SassModule
        getter variables : Hash(String, String)
        getter mixins : Hash(String, MixinClosure)
        getter functions : Hash(String, SassFn)

        def initialize(@variables, @mixins, @functions = {} of String => SassFn)
        end
      end

      # `sass:math` / `sass:string` / ... resolved by `@use "sass:..."`.
      # Built eagerly at startup (thread-safe under -Dpreview_mt) and
      # shared as singletons — module-identity checks rely on that.
      BUILTIN_MODULES = begin
        modules = {} of String => SassModule
        Builtins::MODULE_TABLES.each do |name, tables|
          fns, vars = tables
          functions = {} of String => SassFn
          fns.each { |fn_name, fn| functions[fn_name] = fn }
          modules[name] = SassModule.new(vars.dup, {} of String => MixinClosure, functions)
        end
        modules
      end

      class Environment
        getter parent : Environment?
        getter variables = {} of String => String
        getter mixins = {} of String => MixinClosure
        getter functions = {} of String => SassFn
        # `@use`d modules — only ever populated on a file's root scope.
        getter modules = {} of String => SassModule
        # Flow-control scopes (@if/@each/@for/@while bodies) don't shadow
        # outer variables — they assign through to them, global included
        # (dart-sass flow-control scoping). That is what makes
        # `@while $i < 4 { $i: $i + 1; }` terminate.
        getter? flow_control : Bool

        def initialize(@parent : Environment? = nil, @flow_control : Bool = false)
        end

        def root? : Bool
          @parent.nil?
        end

        def root : Environment
          env = self
          while parent = env.parent
            env = parent
          end
          env
        end

        def lookup_var(name : String) : String?
          name = Sass.normalize_ident(name)
          env : Environment? = self
          while env
            if value = env.variables[name]?
              return value
            end
            env = env.parent
          end
          nil
        end

        # Assignment semantics (dart-sass-flavored):
        # - `!global` writes the root scope (skipped by `!default` when set).
        # - `!default` is a no-op when the name resolves anywhere in scope.
        # - Otherwise the innermost non-root scope already declaring the
        #   name is updated; failing that, the name is declared here —
        #   which shadows a root/global variable rather than mutating it.
        # - Exception: when every frame between here and the root is a
        #   flow-control scope, a root declaration is assigned, not
        #   shadowed (dart-sass flow-control scoping).
        def assign_var(name : String, value : String, default : Bool, global : Bool) : Nil
          name = Sass.normalize_ident(name)
          if global
            return if default && root.variables.has_key?(name)
            root.variables[name] = value
            return
          end
          return if default && lookup_var(name)
          env : Environment? = self
          transparent = true # all frames walked so far are flow-control
          while env
            if env.variables.has_key?(name)
              break if env.root? && !transparent
              env.variables[name] = value
              return
            end
            transparent = false unless env.flow_control?
            env = env.parent
          end
          @variables[name] = value
        end

        def lookup_mixin(name : String) : MixinClosure?
          name = Sass.normalize_ident(name)
          env : Environment? = self
          while env
            if closure = env.mixins[name]?
              return closure
            end
            env = env.parent
          end
          nil
        end

        def declare_mixin(name : String, closure : MixinClosure) : Nil
          @mixins[Sass.normalize_ident(name)] = closure
        end

        def lookup_function(name : String) : SassFn?
          name = Sass.normalize_ident(name)
          env : Environment? = self
          while env
            if fn = env.functions[name]?
              return fn
            end
            env = env.parent
          end
          nil
        end

        def declare_function(name : String, closure : SassFn) : Nil
          @functions[Sass.normalize_ident(name)] = closure
        end

        def declare_module(namespace : String, mod : SassModule) : Bool
          namespace = Sass.normalize_ident(namespace)
          scope = root
          return false if scope.modules.has_key?(namespace)
          scope.modules[namespace] = mod
          true
        end

        def module?(namespace : String) : SassModule?
          root.modules[Sass.normalize_ident(namespace)]?
        end
      end
    end
  end
end
