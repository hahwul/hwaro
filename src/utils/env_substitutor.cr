# Environment variable substitution for config files and templates
#
# Supports:
# - ${VAR} or $VAR - substitute with env var value
# - ${VAR:-default} - substitute with default if VAR is unset or empty
# - Warns on missing env vars without defaults

module Hwaro
  module Utils
    module EnvSubstitutor
      # Combined regex: matches ${VAR}, ${VAR:-default}, or bare $VAR in a single pass.
      # This avoids double-substitution where a replaced value could contain $-patterns.
      #
      # Group 1: braced var name          (from ${VAR} or ${VAR:-default})
      # Group 2: default value            (from ${VAR:-default}, nil when absent)
      # Group 3: bare var name            (from $VAR)
      #
      # NOTE: Nested ${...} in default values is not supported.
      # Use a flat default value: ${VAR:-fallback}
      PATTERN = /\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-(.*?))?\}|\$([A-Za-z_][A-Za-z0-9_]*)\b/

      # Substitute environment variables in the given string.
      # Returns the substituted string and a list of missing variable names.
      #
      # Semantics (aligned with POSIX shell):
      # - ${VAR}          → value if set (even empty), original text + warning if unset
      # - ${VAR:-default} → value if set AND non-empty, otherwise default
      # - $VAR            → value if set (even empty), original text + warning if unset
      def self.substitute(input : String) : {String, Array(String)}
        missing = Set(String).new

        result = input.gsub(PATTERN) do |match|
          braced_name = $1?
          default_value = $2?
          bare_name = $3?

          if braced_name
            has_default = match.includes?(":-")
            env_value = ENV[braced_name]?

            if has_default
              # ${VAR:-default} — use default when unset or empty
              if env_value && !env_value.empty?
                env_value
              else
                default_value || ""
              end
            else
              # ${VAR} — substitute if set (even empty), warn if unset
              if !env_value.nil?
                env_value
              else
                missing.add(braced_name)
                match
              end
            end
          elsif bare_name
            # $VAR — substitute if set (even empty), warn if unset
            env_value = ENV[bare_name]?

            if !env_value.nil?
              env_value
            else
              missing.add(bare_name)
              match
            end
          else
            match
          end
        end

        {result, missing.to_a}
      end

      # Substitute and log warnings for missing variables
      def self.substitute_with_warnings(input : String, source : String = "config") : String
        result, missing = substitute(input)

        missing.each do |var_name|
          Logger.warn "Environment variable '#{var_name}' is not set (referenced in #{source})"
        end

        result
      end
    end
  end
end
