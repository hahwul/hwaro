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
      # Default values may contain `}` as long as it's inside balanced braces.
      PATTERN = /\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*(?:\{[^}]*\}[^}]*)*))?\}|\$([A-Za-z_][A-Za-z0-9_]*)\b/

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

      # Where a placeholder sits in a TOML document, which decides how its
      # value is inserted (see `substitute_toml`).
      private enum TomlContext
        Bare    # a bare value or key: inserted as TOML source
        Basic   # inside "..." or """...""": escaped
        Literal # inside '...' or '''...''': inserted verbatim (no escapes exist)
      end

      # Substitute placeholders in a TOML document without letting a value
      # change its TOML syntax. `substitute` splices text blindly, which
      # config loading cannot afford: a value holding `"` broke the load, a
      # `\` was re-read as an escape (`C:\new` turned into a newline) and a
      # `$VAR` in a `#` comment was substituted and warned about.
      #
      # - inside a basic string an environment value is escaped, so it lands
      #   as exactly the characters the variable holds;
      # - a `${VAR:-default}` default is inserted as written: it is TOML the
      #   author already escaped;
      # - a bare placeholder (`paginate = ${N}`) is still inserted raw, so
      #   numbers, booleans and whole values keep working;
      # - comments are never substituted.
      def self.substitute_toml(input : String) : {String, Array(String)}
        missing = Set(String).new
        bytes = input.to_slice
        size = bytes.size
        output = String.build(input.bytesize) do |io|
          i = 0
          # `delimiter` is the closing quote run of the string we are in
          # ("", "\"", "'", "\"\"\"" or "'''"); empty outside strings.
          delimiter = ""
          while i < size
            byte = bytes[i]
            if delimiter.empty?
              case byte
              when '#'.ord
                line_end = input.byte_index('\n', i) || size
                io.write(bytes[i, line_end - i])
                i = line_end
                next
              when '"'.ord, '\''.ord
                quote = byte.unsafe_chr
                delimiter = input.byte_slice(i, 3) == quote.to_s * 3 ? quote.to_s * 3 : quote.to_s
                io << delimiter
                i += delimiter.bytesize
                next
              end
            else
              if delimiter.starts_with?('"') && byte == '\\'.ord
                # An escape: copy it and the escaped byte untouched.
                io.write(bytes[i, Math.min(2, size - i)])
                i += 2
                next
              end
              if input.byte_slice(i, delimiter.bytesize) == delimiter
                io << delimiter
                i += delimiter.bytesize
                delimiter = ""
                next
              end
              # An unterminated single-line string ends at the line; let the
              # TOML parser report it rather than carrying string state on.
              delimiter = "" if byte == '\n'.ord && delimiter.bytesize == 1
            end

            if byte == '$'.ord && (m = PATTERN.match_at_byte_index(input, i)) && m.byte_begin(0) == i
              context = if delimiter.empty?
                          TomlContext::Bare
                        elsif delimiter.starts_with?('"')
                          TomlContext::Basic
                        else
                          TomlContext::Literal
                        end
              io << resolve_toml(m, context, missing)
              i = m.byte_end(0)
              next
            end

            io.write_byte(byte)
            i += 1
          end
        end
        {output, missing.to_a}
      end

      # One placeholder's replacement: the same POSIX-shell semantics as
      # `substitute`, with an environment value escaped for a basic string.
      private def self.resolve_toml(m : Regex::MatchData, context : TomlContext, missing : Set(String)) : String
        name = m[1]? || m[3]
        env_value = ENV[name]?
        if m[1]? && m[0].includes?(":-")
          return escape_toml_value(env_value, context) if env_value && !env_value.empty?
          return m[2]? || ""
        end
        if env_value.nil?
          missing.add(name)
          return m[0]
        end
        escape_toml_value(env_value, context)
      end

      private def self.escape_toml_value(value : String, context : TomlContext) : String
        return value unless context.basic?
        String.build(value.bytesize) do |io|
          value.each_char do |char|
            case char
            when '\\' then io << "\\\\"
            when '"'  then io << "\\\""
            when '\n' then io << "\\n"
            when '\r' then io << "\\r"
            when '\t' then io << "\\t"
            else
              if char.ascii_control?
                io << "\\u" << char.ord.to_s(16).rjust(4, '0')
              else
                io << char
              end
            end
          end
        end
      end

      # Substitute and log warnings for missing variables
      def self.substitute_with_warnings(input : String, source : String = "config") : String
        result, missing = substitute_toml(input)

        missing.each do |var_name|
          Logger.warn "Environment variable '#{var_name}' is not set (referenced in #{source})"
        end

        result
      end
    end
  end
end
