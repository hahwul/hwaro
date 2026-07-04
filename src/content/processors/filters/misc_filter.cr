require "crinja"
require "json"

module Hwaro
  module Content
    module Processors
      module Filters
        module MiscFilters
          # Recursively serialize a Crinja value tree into a JSON::Builder.
          # Direct `target.to_json(io)` cannot be used here — Crinja::Value#to_json
          # opens its own document and raises inside an already-open builder.
          def self.build_json(json : JSON::Builder, value : Crinja::Value)
            build_json(json, value.raw)
          end

          def self.build_json(json : JSON::Builder, raw)
            case raw
            when Crinja::Value      then build_json(json, raw.raw)
            when Crinja::SafeString then json.string(raw.to_s)
            when Array              then json.array { raw.each { |v| build_json(json, v) } }
            when Hash               then json.object { raw.each { |k, v| json.field(k.to_s) { build_json(json, v) } } }
            when String, Int32, Int64, Float64, Bool, Nil
              raw.to_json(json)
            else
              json.string(raw.to_s)
            end
          end

          def self.register(env : Crinja)
            # JSON encode filter (escapes </ to prevent script-tag breakout in inline JS).
            # Serialize the actual value tree — `target.to_s.to_json` would stringify
            # the Crinja::Value first and emit broken JSON (e.g. "[Crinja::Value<...>]")
            # for arrays/hashes/numbers.
            env.filters["jsonify"] = Crinja.filter do
              JSON.build { |b| MiscFilters.build_json(b, target) }.gsub("</", "<\\/")
            end

            # Override Crinja's built-in `tojson`. Crinja wraps its output in
            # `SafeString.escape`, which HTML-entity-escapes the JSON (`"` ->
            # `&quot;`, `&` -> `&amp;`) — that is invalid JSON in a standalone
            # `.json`/output-format file, and also unusable inside a <script>
            # (browsers don't HTML-decode there). Emit real JSON like `jsonify`
            # while keeping the documented `tojson` name and its optional
            # `indent` argument (spaces) working; `</` stays escaped so the
            # result is still safe to embed in an inline <script>.
            env.filters["tojson"] = Crinja.filter({indent: nil}) do
              raw_indent = arguments["indent"].raw
              # Clamp on the raw Int (Crinja stores it as Int64) BEFORE building
              # the spaces string: a negative count makes `String#*` raise
              # ArgumentError (aborting the whole build), and a huge one would
              # overflow `to_i` or allocate a giant per-level indent. 0..16 is a
              # sane range for JSON indentation.
              indent_str = raw_indent.is_a?(Int) ? " " * raw_indent.clamp(0, 16) : ""
              JSON.build(indent_str) { |b| MiscFilters.build_json(b, target) }.gsub("</", "<\\/")
            end

            # Default filter — returns fallback when target is nil/undefined or empty string
            env.filters["default"] = Crinja.filter({value: ""}) do
              if target.raw.nil? || target.undefined?
                arguments["value"].to_s
              else
                val = target.to_s
                val.empty? ? arguments["value"].to_s : val
              end
            end

            # Inspect filter — outputs debug representation of a value
            env.filters["inspect"] = Crinja.filter do
              raw = target.raw
              case raw
              when Nil
                "nil"
              when String
                raw.inspect
              when Bool, Int32, Int64, Float64
                raw.to_s
              when Array
                String.build do |io|
                  io << "["
                  target.as_a.each_with_index do |v, i|
                    io << ", " if i > 0
                    io << v.to_s
                  end
                  io << "]"
                end
              when Hash
                pairs = [] of String
                target.as_h.each do |k, v|
                  pairs << "#{k}: #{v}"
                end
                "{#{pairs.join(", ")}}"
              else
                target.to_s.inspect
              end
            end
          end
        end
      end
    end
  end
end
