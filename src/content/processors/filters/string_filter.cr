require "crinja"
require "../../../utils/crinja_utils"

module Hwaro
  module Content
    module Processors
      module Filters
        module StringFilters
          def self.register(env : Crinja)
            # Truncate words filter
            env.filters["truncate_words"] = Crinja.filter({length: 50, end: "..."}) do
              # Strip first: a leading-whitespace input would otherwise split into
              # a leading "" token, consuming a word slot and emitting a stray
              # leading space (off-by-one truncation).
              text = target.to_s.strip
              # Lenient coercion: a quoted `length="20"` (which is all a
              # shortcode can forward) used to fall into the `rescue` and
              # silently mean 50, and a negative count sliced `words[0...-n]`
              # and dropped words off the END of the text.
              # `max:` leaves one unit of headroom for the `+ 1` below. to_count
              # saturates out-of-range input at `max` instead of raising, so a
              # `length=2147483647` (or anything larger, which clamps to the
              # same value) landed on Int32::MAX and made `length + 1` raise
              # OverflowError — aborting the render of the whole page, where
              # the intended behaviour for an over-large length is "return the
              # text untouched".
              length = Utils::CrinjaUtils.to_count(arguments["length"], default: 50, max: Int32::MAX - 1)
              ending = arguments["end"].to_s

              # Split one past the limit so `words.size > length` can tell
              # "exactly length words" from "more than length words".
              words = text.split(/\s+/, limit: length + 1)
              if words.size > length
                words[0...length].join(" ") + ending
              else
                text
              end
            end

            # Slugify filter (delegates to TextUtils for CJK support)
            env.filters["slugify"] = Crinja.filter do
              Utils::TextUtils.slugify(target.to_s)
            end

            # Split filter
            env.filters["split"] = Crinja.filter({pat: ","}) do
              text = target.to_s
              separator = arguments["pat"].to_s
              parts = text.split(separator).map { |s| Crinja::Value.new(s.strip) }
              Crinja::Value.new(parts)
            end

            # Trim filter
            env.filters["trim"] = Crinja.filter do
              target.to_s.strip
            end
          end
        end
      end
    end
  end
end
