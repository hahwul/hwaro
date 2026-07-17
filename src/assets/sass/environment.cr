# Lexical scoping for the SCSS evaluator.
#
# Values are plain Strings in the v1 subset (verbatim CSS text after
# variable/interpolation substitution). When SassScript arithmetic lands,
# a Value hierarchy (Number/Color/Bool/List) replaces the String alias —
# the Environment API is already shaped for it.

require "./ast"

module Hwaro
  module Assets
    module Sass
      # Mixins close over their definition environment (dart-sass
      # semantics); `path` keeps error locations pointing at the file the
      # mixin was defined in, not the include site.
      record MixinClosure, node : Ast::MixinDefNode, env : Environment, path : String

      # A loaded `@use` module: its root-scope members plus nothing else
      # (module-private state stays in the closed-over environments).
      class SassModule
        getter variables : Hash(String, String)
        getter mixins : Hash(String, MixinClosure)

        def initialize(@variables, @mixins)
        end
      end

      class Environment
        getter parent : Environment?
        getter variables = {} of String => String
        getter mixins = {} of String => MixinClosure
        # `@use`d modules — only ever populated on a file's root scope.
        getter modules = {} of String => SassModule

        def initialize(@parent : Environment? = nil)
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
        def assign_var(name : String, value : String, default : Bool, global : Bool) : Nil
          if global
            return if default && root.variables.has_key?(name)
            root.variables[name] = value
            return
          end
          return if default && lookup_var(name)
          env : Environment? = self
          while env && !env.root?
            if env.variables.has_key?(name)
              env.variables[name] = value
              return
            end
            env = env.parent
          end
          @variables[name] = value
        end

        def lookup_mixin(name : String) : MixinClosure?
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
          @mixins[name] = closure
        end

        def declare_module(namespace : String, mod : SassModule) : Bool
          scope = root
          return false if scope.modules.has_key?(namespace)
          scope.modules[namespace] = mod
          true
        end

        def module?(namespace : String) : SassModule?
          root.modules[namespace]?
        end
      end
    end
  end
end
