# Depth guard for the recursive value converters (YAML/JSON/TOML::Any →
# ExtraValue / Crinja::Value / each other).
#
# `src/ext/toml_nesting_limit_fix.cr` caps how deep a document may nest in the
# SOURCE, which is enough for TOML and JSON: their parsers can only ever build
# a tree, so a bounded source means bounded traversal. YAML is different — an
# alias may point at one of its own ancestors:
#
#     ---
#     x: &a
#       b: *a
#     ---
#
# Crystal's `YAML.parse` accepts that happily and hands back a `YAML::Any`
# whose object graph is CYCLIC. Two lines of front matter, three levels of
# source nesting, and every recursive walker over the result runs forever:
# `Markdown#extract_extra_value` blew the stack at ~8000 frames and took the
# whole build down with `Stack overflow`, exit 11. Crystal cannot rescue a
# stack overflow, so the call sites' careful `rescue` clauses never ran.
#
# A cycle is invisible to any source-level limit, so the guard has to live in
# the traversal. Every recursive converter threads a `depth` and calls
# `Nesting.check!` on entry; `TooDeep` is an ordinary exception, so the call
# sites that already degrade gracefully on a malformed data file (warn and drop
# the key) keep doing exactly that, and the front-matter path turns it into the
# same `HWARO_E_CONTENT` error a syntax error produces.
module Hwaro
  module Utils
    module Nesting
      # Same value as `TOML::Parser::HWARO_MAX_NESTING` and Crystal's
      # `JSON::PullParser`/`YAML` MAX_NESTING. Any document that parses at all
      # is already capped at 512 levels of real nesting, so this can only fire
      # on a cycle — no valid input reaches it.
      MAX_VALUE_DEPTH = 512

      class TooDeep < Exception
        def initialize(message : String? = nil)
          super(message || "value nesting exceeds #{MAX_VALUE_DEPTH} levels " \
                           "(a self-referencing YAML anchor such as `x: &a\\n  b: *a` is the usual cause)")
        end
      end

      # Raises once the walk is deeper than any real document can be.
      def self.check!(depth : Int32) : Nil
        raise TooDeep.new if depth > MAX_VALUE_DEPTH
      end

      # Validate a `YAML::Any` subtree before handing it to a serializer that
      # has no depth parameter of its own — `YAML::Any#to_json` and `#to_s`
      # both recurse the raw graph, so on a cyclic value they blow the stack
      # where a `depth` thread would have raised. Walk it first; the walk is
      # bounded, the serializer that follows is then known to be too.
      def self.validate!(value : YAML::Any, depth : Int32 = 0) : Nil
        check!(depth)
        case raw = value.raw
        when Array
          raw.each { |item| validate!(item, depth + 1) }
        when Hash
          raw.each do |k, v|
            validate!(k, depth + 1)
            validate!(v, depth + 1)
          end
        end
      end
    end
  end
end
