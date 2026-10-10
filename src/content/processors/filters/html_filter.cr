require "crinja"
require "markd"
require "../../../utils/text_utils"

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

            # Markdownify filter. Honors the site's [markdown] safe and
            # smart_punctuation settings (published once per build via
            # Processor::Markdown.filter_markdown_config); with no site
            # config — library/spec contexts — it keeps markd's bare
            # defaults. The full extension pipeline (tables, heading ids,
            # highlighting) is deliberately NOT applied here: routing it
            # would change bytes for every existing `| markdownify` call.
            env.filters["markdownify"] = Crinja.filter do
              if cfg = Hwaro::Processor::Markdown.filter_markdown_config
                text = target.to_s
                options = Markd::Options.new(safe: cfg.safe, smart: cfg.smart_punctuation)
                if cfg.safe && text.includes?("<!--HWARO-SHORTCODE-PLACEHOLDER-")
                  # A block body (`{% alert %}A {{ youtube(...) }}{% end %}`)
                  # carries its nested shortcodes as placeholder comments,
                  # which plain Markd safe mode erased. Keep them, as the
                  # page body's renderer does; documented "shortcode output
                  # is kept".
                  HighlightingRenderer.new(options, false).render(Markd::Parser.parse(text, options))
                else
                  Markd.to_html(text, options)
                end
              else
                Markd.to_html(target.to_s)
              end
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
