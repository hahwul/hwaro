require "file_utils"
require "../../models/config"
require "../../models/page"
require "../../utils/logger"

module Hwaro
  module Content
    module Seo
      class Amp
        # Generate AMP versions of rendered pages.
        # Reads the already-rendered HTML files, converts to AMP-compliant HTML,
        # and writes them under the configured path prefix.
        def self.generate(
          pages : Array(Models::Page),
          config : Models::Config,
          output_dir : String,
          verbose : Bool = false,
        )
          return unless config.amp.enabled

          amp_config = config.amp
          prefix = amp_config.path_prefix.strip('/')
          generated = 0

          pages.each do |page|
            next if page.draft
            next if page.generated
            next unless page.render
            next unless amp_config.section_enabled?(page.section)

            # Read the canonical rendered HTML
            canonical_path = output_path_for(page, output_dir)
            next unless File.exists?(canonical_path)

            html = File.read(canonical_path)
            amp_html = convert_to_amp(html, page, config)

            # Write AMP version
            amp_output = amp_output_path(page, output_dir, prefix)
            unless Utils::OutputGuard.within_output_dir?(amp_output, output_dir)
              Logger.warn "  [WARN] Skipping AMP output outside output directory: #{amp_output}"
              next
            end
            dir = File.dirname(amp_output)
            FileUtils.mkdir_p(dir) unless Dir.exists?(dir)
            File.write(amp_output, amp_html)

            # Inject <link rel="amphtml"> into the canonical page
            inject_amphtml_link(canonical_path, page, config, prefix)

            generated += 1
            Logger.debug "  AMP: #{amp_output}" if verbose
          end

          Logger.info "  Generated #{generated} AMP page(s)" if generated > 0
        end

        # Convert standard HTML to AMP-compliant HTML
        def self.convert_to_amp(html : String, page : Models::Page, config : Models::Config) : String
          result = html

          # Add AMP boilerplate to <html> tag
          result = result.sub(/<html([^>]*)>/i, %(<html amp\\1>))

          # Remove disallowed tags: <script> (except application/ld+json and amp scripts)
          # Use [\s\S]*? instead of .*? to match across newlines
          result = result.gsub(/<script(?![^>]*type=["']application\/ld\+json["'])(?![^>]*(?:async|custom-element|src=["']https:\/\/cdn\.ampproject\.org))[^>]*>[\s\S]*?<\/script>/mi, "")

          # Remove style attributes and JS event handlers BEFORE element conversion
          # (so that container divs added by amp-img conversion aren't affected)
          result = result.gsub(/\s+style=["'][^"']*["']/i, "")
          result = result.gsub(/\s+on\w+=["'][^"']*["']/i, "")

          # Convert <img> to <amp-img>
          result = result.gsub(/<img([^>]*)\/?>/mi) do
            attrs = $1
            has_width = attrs.includes?("width=")
            has_height = attrs.includes?("height=")

            if has_width && has_height
              # Explicit dimensions: use responsive layout
              unless attrs.includes?("layout=")
                attrs += %( layout="responsive")
              end
              %(<amp-img#{attrs}></amp-img>)
            else
              # No dimensions: use fill layout inside a positioned container
              attrs += %( layout="fill") unless attrs.includes?("layout=")
              %(<div class="amp-img-container"><amp-img#{attrs}></amp-img></div>)
            end
          end

          # Convert <video> to <amp-video>
          result = result.gsub(/<video([^>]*)>(.*?)<\/video>/mi) do
            %(<amp-video#{$1} layout="responsive">#{$2}</amp-video>)
          end

          # Convert <iframe> to <amp-iframe>
          result = result.gsub(/<iframe([^>]*)>(.*?)<\/iframe>/mi) do
            attrs = $1
            unless attrs.includes?("layout=")
              attrs += %( layout="responsive")
            end
            %(<amp-iframe#{attrs}>#{$2}</amp-iframe>)
          end

          # Inject AMP boilerplate CSS in <head> if not already present
          unless result.includes?("amp-boilerplate")
            amp_boilerplate = <<-HTML
            <style amp-boilerplate>body{-webkit-animation:-amp-start 8s steps(1,end) 0s 1 normal both;-moz-animation:-amp-start 8s steps(1,end) 0s 1 normal both;animation:-amp-start 8s steps(1,end) 0s 1 normal both}@-webkit-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@-moz-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@-ms-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@-o-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}</style><noscript><style amp-boilerplate>body{-webkit-animation:none;-moz-animation:none;-ms-animation:none;animation:none}</style></noscript>
            <style amp-custom>.amp-img-container{position:relative;width:100%;min-height:200px}</style>
            <script async src="https://cdn.ampproject.org/v0.js"></script>
            HTML
            result = result.sub(/<\/head>/i, "#{amp_boilerplate}\n</head>")
          end

          # Add canonical link to the original page
          base_url = config.base_url.rstrip('/')
          canonical_url = Utils::TextUtils.escape_xml("#{base_url}#{page.url}")
          unless result.includes?("rel=\"canonical\"")
            result = result.sub(/<\/head>/i, %(<link rel="canonical" href="#{canonical_url}">\n</head>))
          end

          result
        end

        # Inject <link rel="amphtml"> into the canonical page's HTML
        private def self.inject_amphtml_link(
          canonical_path : String,
          page : Models::Page,
          config : Models::Config,
          prefix : String,
        )
          html = File.read(canonical_path)
          return if html.includes?("rel=\"amphtml\"")

          base_url = config.base_url.rstrip('/')
          amp_url = Utils::TextUtils.escape_xml("#{base_url}/#{prefix}#{page.url}")
          link_tag = %(<link rel="amphtml" href="#{amp_url}">)

          updated = html.sub(/<\/head>/i, "#{link_tag}\n</head>")
          File.write(canonical_path, updated)
        end

        private def self.output_path_for(page : Models::Page, output_dir : String) : String
          url_path = page.url.sub(/^\//, "")
          File.join(output_dir, url_path, "index.html")
        end

        private def self.amp_output_path(page : Models::Page, output_dir : String, prefix : String) : String
          url_path = page.url.sub(/^\//, "")
          File.join(output_dir, prefix, url_path, "index.html")
        end
      end
    end
  end
end
