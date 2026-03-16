require "crinja"
require "markd"
require "../../../../src/utils/text_utils"

module Hwaro
  module Content
    module Processors
      module Filters
        module HtmlFilters
          def self.register(env : Crinja)
            # Strip HTML tags filter (delegates to TextUtils for robust tag handling)
            env.filters["strip_html"] = Crinja.filter do
              Hwaro::Utils::TextUtils.strip_html(target.to_s)
            end

            # Markdownify filter
            env.filters["markdownify"] = Crinja.filter do
              Markd.to_html(target.to_s)
            end

            # XML escape filter (single-pass via TextUtils)
            env.filters["xml_escape"] = Crinja.filter do
              Hwaro::Utils::TextUtils.escape_xml(target.to_s)
            end

            # Safe filter
            env.filters["safe"] = Crinja.filter do
              Crinja::Value.new(Crinja::SafeString.new(target.to_s))
            end
          end
        end
      end
    end
  end
end
