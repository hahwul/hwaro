# Config section — generic TOML parsing, validation and value coercion helpers.
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    class Config
      # Reject a NUL byte anywhere in a config string — value OR key.
      #
      # A NUL survives TOML parsing (the `\u0000` escape is well-formed, in a
      # quoted key just as in a value) but every filesystem call built from
      # that string raises a bare `ArgumentError: String contains null byte`
      # from deep inside stdlib — `Path.new`'s `check_no_null_byte`. That
      # reached the CLI as the unclassified `Error: String contains null
      # byte`, with no file, no key and no hint, from seven keys
      # (`[build] output_dir`, the five `filename`/`full_filename` output
      # keys, `[og.auto_image] output_dir`). Individual guards could not catch
      # it: `validate_output_filename!` was itself defeated because its
      # `File.basename(value)` operand raised before the NUL check it guarded
      # could run.
      #
      # KEYS are checked too, not just values: `[languages."e\u0000n"]` puts a
      # NUL into a language code, and `[menus."a\u0000b"]` into a menu name —
      # both of which downstream code joins into output paths. No CLI input
      # reaches that particular `File.join` today, but a key is a config
      # string like any other and the point of a boundary check is not to
      # depend on which consumer happens to be wired up.
      #
      # ITERATIVE, not recursive: `[a.b.c…]` builds one nested table per dotted
      # segment and bypasses the `parse_value` nesting cap in
      # ext/toml_nesting_limit_fix.cr (that cap counts array/inline-table
      # values, which a table HEADER never enters). A 50k-segment header is
      # accepted by the parser, so a recursive walk over the result overflowed
      # the stack — an unrescuable crash on a config the loaders themselves
      # never descend into.
      private def self.reject_null_bytes!(root : Hash(String, TOML::Any), path : String) : Nil
        pending = [] of {TOML::Any | Hash(String, TOML::Any) | Array(TOML::Any), KeyTrail}
        root.each do |k, v|
          reject_null_key!(k, nil, path)
          pending << {v.as(TOML::Any | Hash(String, TOML::Any) | Array(TOML::Any)), KeyTrail.new(k, nil)}
        end

        while entry = pending.pop?
          node, trail = entry
          case node
          when Hash(String, TOML::Any)
            node.each do |k, v|
              reject_null_key!(k, trail, path)
              pending << {v.as(TOML::Any | Hash(String, TOML::Any) | Array(TOML::Any)), KeyTrail.new(".#{k}", trail)}
            end
          when Array(TOML::Any)
            node.each_with_index do |v, i|
              pending << {v.as(TOML::Any | Hash(String, TOML::Any) | Array(TOML::Any)), KeyTrail.new("[#{i}]", trail)}
            end
          when TOML::Any
            raw = node.raw
            case raw
            when String
              next unless raw.includes?(Char::ZERO)
              raise null_byte_error(trail.to_s, path)
            when Hash(String, TOML::Any)
              pending << {raw, trail}
            when Array(TOML::Any)
              pending << {raw, trail}
            end
          end
        end
      end

      # One segment of a dotted key, linked to its parent.
      #
      # The trail is only ever READ on the raise path, so segments are linked
      # rather than concatenated: building `"#{key}.#{k}"` at every node made
      # the walk quadratic in depth, which is exactly the shape (a very deep
      # `[a.b.c…]` header) the iterative rewrite exists to survive — 100k
      # segments cost 6.3s of string building on top of a 0.9s parse.
      private class KeyTrail
        getter segment : String
        getter parent : KeyTrail?

        def initialize(@segment : String, @parent : KeyTrail?)
        end

        def to_s(io : IO) : Nil
          segments = [] of String
          node : KeyTrail? = self
          while current = node
            segments << current.segment
            node = current.parent
          end
          segments.reverse_each { |s| io << s }
        end
      end

      private def self.reject_null_key!(key : String, trail : KeyTrail?, path : String) : Nil
        return unless key.includes?(Char::ZERO)
        raise null_byte_error(trail ? "#{trail}.#{key}" : key, path)
      end

      private def self.null_byte_error(key : String, path : String) : Hwaro::HwaroError
        Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          # The key is capped: a `[a.b.c…]` header can be arbitrarily long, and
          # an unreadable wall of segments is a worse diagnostic than a
          # truncated one.
          message: "#{Utils::TextUtils.truncate_error(key, 200)} in #{path} contains a NUL byte (\\u0000).",
          hint: "Remove the \\u0000 escape from the value; NUL is not valid in a path, filename, URL, or title.",
        )
      end

      # Parse a TOML string, re-raising any parser failure as a classified
      # `HWARO_E_CONFIG` error so the CLI maps it to exit code 3 and the
      # `--json` handlers emit the structured error payload. The hint points
      # users at the offending file so they can fix the syntax.
      private def self.parse_toml(content : String, path : String) : Hash(String, TOML::Any)
        # A BOM'd config.toml (Notepad / PowerShell `>` / "UTF-8 with BOM")
        # otherwise dies on `unexpected char '﻿' at 1:1` — an invisible
        # character the user cannot see in their editor.
        TOML.parse(Utils::TextUtils.strip_bom(content))
      rescue ex : Hwaro::HwaroError
        raise ex
      rescue ex
        # `[versions]` (switch table) and `[[versions]]` (entry array) in one
        # file is the natural first attempt at versioned docs, and TOML
        # rejects it with a bare type mismatch ("expected versions to be an
        # Array"). Name the fix instead of the symptom.
        if mixed_versions_forms?(content)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONFIG,
            message: "Invalid TOML in #{path}: `[versions]` and `[[versions]]` cannot both be used — a key is either a table or an array of tables.",
            hint: "Keep the switches in [versions] and declare each version as [[versions.list]] (or drop the [versions] table and use bare [[versions]] entries with default switches). See https://hwaro.hahwul.com/features/versioned-docs/.",
          )
        end
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: "Invalid TOML in #{path}: #{ex.message}",
          hint: "Check TOML syntax in #{path}.",
        )
      end

      VERSIONS_TABLE_HEADER_RE = /^[ \t]*\[[ \t]*versions[ \t]*\][ \t]*(#.*)?$/m
      VERSIONS_ARRAY_HEADER_RE = /^[ \t]*\[\[[ \t]*versions[ \t]*\]\][ \t]*(#.*)?$/m

      private def self.mixed_versions_forms?(content : String) : Bool
        text = content.scrub
        text.matches?(VERSIONS_TABLE_HEADER_RE) && text.matches?(VERSIONS_ARRAY_HEADER_RE)
      end

      # Deep-merge two TOML hashes.  Values in `override` take precedence.
      # Sub-tables (hashes) are merged recursively; all other types are replaced.
      private def self.deep_merge(
        base : Hash(String, TOML::Any),
        override : Hash(String, TOML::Any),
      ) : Hash(String, TOML::Any)
        merged = base.dup
        override.each do |key, value|
          if base_val = merged[key]?
            base_hash = base_val.as_h?
            over_hash = value.as_h?
            if base_hash && over_hash
              merged[key] = TOML::Any.new(deep_merge(base_hash, over_hash))
            else
              merged[key] = value
            end
          else
            merged[key] = value
          end
        end
        merged
      end

      # Safe boolean loader: returns the parsed Bool if present, otherwise the default.
      # This avoids the `||` pitfall where `false || default` silently ignores `false`.
      private def self.bool_value(raw : TOML::Any?, default : Bool) : Bool
        val = raw.try(&.as_bool?)
        val.nil? ? default : val
      end

      # Safe integer loader: handles both integer and float TOML values.
      # Top-level string field with a default. A present-but-non-string value
      # (`title = 123`, `description = false`) used to fall back to the
      # default with zero feedback, so the site quietly shipped as
      # "Hwaro Site" — the numeric loaders below already warn in that case.
      private def self.string_or_default(raw : Hash(String, TOML::Any), key : String, default : String) : String
        value = raw[key]?
        return default unless value
        value.as_s? || begin
          Logger.warn "Ignoring non-string config value #{key} = #{value.raw.inspect}; using default #{default.inspect}"
          default
        end
      end

      # Uses the 64-bit accessor and clamps to Int32 range so an oversized
      # config value (e.g. `per_page = 9999999999` or `1e30`) yields a clamped
      # Int32 instead of raising OverflowError out of `as_i?`/`to_i` — which
      # would abort the build with an unclassified crash instead of running.
      private def self.int_value(raw : TOML::Any?, default : Int32) : Int32
        return default unless raw
        # `finite?` guard: NaN.clamp is NaN and NaN.to_i64 raises OverflowError,
        # so a `nan`/`-nan` float in config would otherwise crash the build.
        val = raw.as_i64? || raw.as_f?.try { |f| f.finite? ? f.clamp(Int32::MIN.to_f64, Int32::MAX.to_f64).to_i64 : nil }
        unless val
          # Present but not a usable number (e.g. a quoted "20", a bool, NaN) —
          # warn instead of silently using the default with zero feedback.
          Logger.warn "Ignoring non-numeric config value #{raw.raw.inspect}; using default #{default}"
          return default
        end
        val.clamp(Int32::MIN.to_i64, Int32::MAX.to_i64).to_i32
      end

      # Safe float loader: handles both float and integer TOML values.
      # Uses as_i64? (Int64#to_f never overflows) to avoid the OverflowError
      # that as_i? raises for integers above Int32::MAX.
      private def self.float_value(raw : TOML::Any?, default : Float64) : Float64
        return default unless raw
        val = raw.as_f? || raw.as_i64?.try(&.to_f)
        unless val
          Logger.warn "Ignoring non-numeric config value #{raw.raw.inspect}; using default #{default}"
          return default
        end
        val
      end

      # Non-raising Int32 extraction from a single TOML value (nil if absent or
      # non-numeric). Clamps to Int32 range like int_value so an oversized value
      # never raises OverflowError out of as_i?/to_i at the inline call sites.
      private def self.int_or_nil(raw : TOML::Any) : Int32?
        val = raw.as_i64? || raw.as_f?.try { |f| f.finite? ? f.clamp(Int32::MIN.to_f64, Int32::MAX.to_f64).to_i64 : nil }
        val.try(&.clamp(Int32::MIN.to_i64, Int32::MAX.to_i64).to_i32)
      end

      # Extracts a string-or-array TOML value into an Array(String).
      private def self.string_or_array(raw : TOML::Any?) : Array(String)
        return [] of String unless raw
        raw.as_a?.try(&.compact_map(&.as_s?)) ||
          raw.as_s?.try { |v| [v] } ||
          [] of String
      end

      # Basenames that do not name a file. Every generated-file emitter
      # (sitemap, robots, search, feeds, llms) writes to
      # `Path[output_dir, File.basename(configured_filename)]`, and
      # `File.basename` maps each of these back to itself — so the write target
      # collapses onto the output DIRECTORY instead of a file inside it. The
      # atomic writer then tries to rename its temp file onto a directory and
      # the build dies with a raw `IO::Error` naming an internal
      # `.<pid>.<fiber>.tmp` path under exit 70, the code this project reserves
      # for internal bugs.
      NON_FILE_BASENAMES = {"", ".", "..", "/"}

      # Reject a `[<table>] <key>` value that cannot become a file inside the
      # output directory, with a classified config error naming the key instead
      # of the internal temp-file IO::Error the emitters would otherwise raise.
      #
      # `allow_empty` is for the two keys where the empty string already means
      # "use the built-in default" (`[feeds] filename` defaults to `""`, and
      # llms.cr substitutes its defaults for an empty value) — rejecting those
      # would break configs that build correctly today.
      private def self.validate_output_filename!(table : String, key : String, value : String, example : String, allow_empty : Bool) : Nil
        return if allow_empty && value.empty?
        # A NUL byte survives both TOML and File.basename, and then raises a
        # bare `ArgumentError: String contains null byte` out of the writer.
        # NUL FIRST: `File.basename` builds a `Path`, whose `check_no_null_byte`
        # raises a bare ArgumentError before the `||` could ever reach the NUL
        # test on its right. Ordering the cheap, non-raising check first is
        # what makes this guard able to report the case it was written for.
        return unless value.includes?(Char::ZERO) || NON_FILE_BASENAMES.includes?(File.basename(value))

        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: "Invalid [#{table}] #{key} = #{value.inspect}: it does not name a file.",
          hint: "Set #{key} to a plain filename such as \"#{example}\", or remove the key to use the default.",
        )
      end
    end
  end
end
