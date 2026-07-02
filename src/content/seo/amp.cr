require "file_utils"
require "../../models/config"
require "../../models/page"
require "../../utils/logger"

module Hwaro
  module Content
    module Seo
      class Amp
        # Font providers AMP allows via `<link rel="stylesheet">`. Every other
        # external stylesheet is disallowed and is stripped during conversion.
        AMP_FONT_PROVIDERS = %w[
          cloud.typography.com
          fast.fonts.net
          fonts.googleapis.com
          use.typekit.net
          maxcdn.bootstrapcdn.com
          use.fontawesome.com
          fonts.bunny.net
        ]

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
          # A blank/slash-only prefix would make amp_output_path collapse to the
          # canonical path (File.join drops empty components), overwriting every
          # canonical page with its AMP variant. Refuse rather than destroy output.
          if prefix.empty?
            Logger.warn "AMP path_prefix resolves to empty; skipping AMP generation to avoid overwriting canonical pages."
            return
          end
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
              Logger.warn "Skipping AMP output outside output directory: #{amp_output}"
              next
            end
            dir = File.dirname(amp_output)
            Hwaro::Utils::FileSafe.mkdir_p(dir) unless Dir.exists?(dir)
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

          # Strip any self-referencing <link rel="amphtml"> left over from a
          # prior build (the on-disk canonical HTML may already carry one). An
          # AMP page must never reference an amphtml variant of itself, so make
          # the conversion idempotent across repeat/cached builds.
          result = result.gsub(/<link\b[^>]*rel=["']amphtml["'][^>]*>\s*/i, "")

          # Add AMP boilerplate to <html> tag
          result = result.sub(/<html([^>]*)>/i, %(<html amp\\1>))

          # Remove disallowed tags: <script> (except application/ld+json and amp scripts)
          # Use [\s\S]*? instead of .*? to match across newlines
          # The `async`/`custom-element` exceptions must be anchored to real
          # attribute boundaries (preceded by whitespace, followed by a value /
          # tag terminator); otherwise a substring match like `id="async"` would
          # cause an author `<script>` to survive into the AMP page. The
          # cdn.ampproject.org src allowlist stays in its own lookahead.
          result = result.gsub(/<script(?![^>]*type=["']application\/ld\+json["'])(?![^>]*\s(?:async|custom-element)(?:\s|=|>|\/))(?![^>]*src=["']https:\/\/cdn\.ampproject\.org)[^>]*>[\s\S]*?<\/script>/mi, "")

          # Remove disallowed external stylesheets. AMP forbids
          # `<link rel="stylesheet">` except from allowlisted font providers;
          # all other CSS must live in a single `<style amp-custom>`. Without
          # this the site CSS and highlight.js/KaTeX CDN links make every AMP
          # page fail validation.
          result = result.gsub(/<link\b[^>]*>/i) do |tag|
            if tag =~ /rel=["']stylesheet["']/i
              href = tag.match(/href=["']([^"']*)["']/i).try(&.[1]) || ""
              AMP_FONT_PROVIDERS.any? { |provider| href.includes?(provider) } ? tag : ""
            else
              tag
            end
          end

          # Remove style attributes and JS event handlers BEFORE element conversion
          # (so that container divs added by amp-img conversion aren't affected)
          result = result.gsub(/\s+style=["'][^"']*["']/i, "")
          result = result.gsub(/\s+on\w+=["'][^"']*["']/i, "")

          # Convert <img> to <amp-img>. Quote-aware attribute scan (same
          # pattern as IMG_LAZY_REGEX in markdown.cr): a `>` inside a quoted
          # attribute value (legal HTML5, e.g. alt="Home > Docs") must not be
          # treated as the tag end, or the conversion emits a broken
          # `<amp-img … alt="Home ></amp-img> Docs" />`.
          result = result.gsub(/<img((?:[^>"']|"[^"]*"|'[^']*')*?)\s*\/?>/mi) do
            # `[^>]*` greedily swallows the self-closing slash from `<img … />`,
            # which would otherwise be appended mid-tag as
            # `<amp-img … / layout="…">` — invalid AMP. Strip a trailing slash.
            attrs = $1.sub(/\s*\/\s*$/, "")
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

          # A block-level <div class="amp-img-container"> placed directly inside
          # a <p> (Markdown wraps a standalone image in a paragraph) is invalid
          # HTML. Unwrap any <p> whose sole child is that container div.
          result = result.gsub(/<p>(\s*<div class="amp-img-container">[\s\S]*?<\/div>\s*)<\/p>/mi) { $1 }

          # Convert <video> to <amp-video>
          needs_amp_video = false
          result = result.gsub(/<video([^>]*)>(.*?)<\/video>/mi) do
            needs_amp_video = true
            %(<amp-video#{$1} layout="responsive">#{$2}</amp-video>)
          end

          # Convert <iframe> to <amp-iframe>
          needs_amp_iframe = false
          result = result.gsub(/<iframe([^>]*)>(.*?)<\/iframe>/mi) do
            needs_amp_iframe = true
            attrs = $1
            unless attrs.includes?("layout=")
              attrs += %( layout="responsive")
            end
            # amp-iframe requires a sandbox attribute; add a sane default when
            # the source <iframe> didn't carry one.
            unless attrs.includes?("sandbox=")
              attrs += %( sandbox="allow-scripts allow-same-origin allow-popups")
            end
            %(<amp-iframe#{attrs}>#{$2}</amp-iframe>)
          end

          # Mandatory extension scripts for amp-iframe / amp-video. These must be
          # present in <head> whenever the corresponding element is used.
          amp_iframe_script = %(<script async custom-element="amp-iframe" src="https://cdn.ampproject.org/v0/amp-iframe-0.1.js"></script>)
          amp_video_script = %(<script async custom-element="amp-video" src="https://cdn.ampproject.org/v0/amp-video-0.1.js"></script>)
          extension_scripts = ""
          extension_scripts += "\n#{amp_iframe_script}" if needs_amp_iframe
          extension_scripts += "\n#{amp_video_script}" if needs_amp_video

          # Inject AMP boilerplate CSS in <head> if not already present
          if result.includes?("amp-boilerplate")
            # Boilerplate already present (e.g. theme-supplied). The mandatory
            # amp-iframe / amp-video extension scripts may still be missing —
            # inject any that are needed but not already declared.
            missing = ""
            if needs_amp_iframe && !result.includes?(%(custom-element="amp-iframe"))
              missing += "\n#{amp_iframe_script}"
            end
            if needs_amp_video && !result.includes?(%(custom-element="amp-video"))
              missing += "\n#{amp_video_script}"
            end
            unless missing.empty?
              if result.matches?(/<\/head>/i)
                result = result.sub(/<\/head>/i, "#{missing}\n</head>")
              elsif result.matches?(/<\/body>/i)
                result = result.sub(/<\/body>/i, "#{missing}\n</body>")
              else
                result = "#{result}#{missing}"
              end
            end
          else
            # AMP permits exactly one <style amp-custom> (plus the two mandatory
            # <style amp-boilerplate> blocks). Theme templates inline a bare
            # <style> in <head>; left in place it becomes a second custom
            # stylesheet and fails AMP validation. Extract that CSS, drop the
            # blocks, and fold it into the single amp-custom injected below.
            # Done only on this path so the CSS is never stripped without being
            # re-injected (a theme that already ships its own boilerplate keeps
            # its <style> blocks untouched).
            theme_css = [] of String
            result = result.gsub(/<style(?![^>]*amp-boilerplate)(?![^>]*amp-custom)[^>]*>([\s\S]*?)<\/style>/mi) do
              theme_css << $1
              ""
            end
            # `!important` is disallowed inside amp-custom.
            extracted_css = theme_css.join("\n").gsub(/\s*!important/i, "")

            amp_boilerplate = <<-HTML
              <style amp-boilerplate>body{-webkit-animation:-amp-start 8s steps(1,end) 0s 1 normal both;-moz-animation:-amp-start 8s steps(1,end) 0s 1 normal both;animation:-amp-start 8s steps(1,end) 0s 1 normal both}@-webkit-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@-moz-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@-ms-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@-o-keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}@keyframes -amp-start{from{visibility:hidden}to{visibility:visible}}</style><noscript><style amp-boilerplate>body{-webkit-animation:none;-moz-animation:none;-ms-animation:none;animation:none}</style></noscript>
              <style amp-custom>.amp-img-container{position:relative;width:100%;min-height:200px}#{extracted_css}</style>
              <script async src="https://cdn.ampproject.org/v0.js"></script>#{extension_scripts}
              HTML
            # The AMP runtime/boilerplate is mandatory. If the theme rendered no
            # </head>, fall back to </body> (then end-of-doc) and warn rather than
            # silently emitting an invalid AMP page.
            if result.matches?(/<\/head>/i)
              result = result.sub(/<\/head>/i, "#{amp_boilerplate}\n</head>")
            elsif result.matches?(/<\/body>/i)
              Logger.warn "AMP: no </head> in #{page.url}; injecting AMP boilerplate before </body>."
              result = result.sub(/<\/body>/i, "#{amp_boilerplate}\n</body>")
            else
              Logger.warn "AMP: no </head> or </body> in #{page.url}; AMP page may be invalid."
              result = "#{result}\n#{amp_boilerplate}"
            end
          end

          # Add canonical link to the original page
          base_url = config.base_url.rstrip('/')
          canonical_url = Utils::TextUtils.escape_xml("#{base_url}#{page.url}")
          if !result.includes?("rel=\"canonical\"") && result.matches?(/<\/head>/i)
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

          if html.matches?(/<\/head>/i)
            updated = html.sub(/<\/head>/i, "#{link_tag}\n</head>")
            File.write(canonical_path, updated)
          else
            Logger.warn "AMP: no </head> in #{canonical_path}; cannot inject rel=amphtml link."
          end
        end

        private def self.output_path_for(page : Models::Page, output_dir : String) : String
          url_path = page.url.lchop("/")
          File.join(output_dir, url_path, "index.html")
        end

        private def self.amp_output_path(page : Models::Page, output_dir : String, prefix : String) : String
          url_path = page.url.lchop("/")
          File.join(output_dir, prefix, url_path, "index.html")
        end
      end
    end
  end
end
