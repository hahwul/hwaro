# Render phase — post-render HTML transforms (responsive images, TOC, error overlay).
#
# Reopens `Phases::Render`; the part require order lives in ../render.cr,
# next to the phase's tuning constants. Parts only reopen the module: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro::Core::Build::Phases::Render
  # Rewrite content <img> tags to add `srcset`/`sizes` when the image has
  # generated width variants (see ImageHooks). Only runs when image_processing
  # is enabled and at least one variant exists. A relative `src` is resolved
  # against the page URL to match the resize map keys (which are site-absolute,
  # e.g. `/posts/foo/photo.png`); absolute `src` is used as-is. External
  # (http/protocol-relative/data:) sources and tags that already carry a
  # `srcset` (e.g. emitted by the `resize_image()` helper) are left untouched.
  IMG_TAG_RE = /<img\b[^>]*>/
  IMG_SRC_RE = /\ssrc\s*=\s*("([^"]*)"|'([^']*)')/

  private def apply_responsive_images(html : String, page : Models::Page, config : Models::Config) : String
    return html unless config.image_processing.enabled
    return html unless html.includes?("<img")

    # Read-only view: apply_responsive_images only looks up keys, never
    # mutates. Using the live map avoids a per-page full-map copy plus a
    # contended global mutex on the parallel render hot path.
    resize_map = Content::Hooks::ImageHooks.resize_map_readonly
    return html if resize_map.empty?

    html.gsub(IMG_TAG_RE) do |tag|
      next tag if tag.includes?("srcset")
      m = tag.match(IMG_SRC_RE)
      next tag unless m
      src = m[2]? || m[3]? || ""
      next tag if src.empty?
      next tag if src.starts_with?("http://") || src.starts_with?("https://") ||
                  src.starts_with?("//") || src.starts_with?("data:")

      key = if src.starts_with?("/")
              src
            else
              base = page.url.ends_with?("/") ? page.url : "#{page.url}/"
              "#{base}#{src}".gsub("//", "/")
            end
      # Markdown emits percent-encoded URLs (spaces/unicode), but the resize map
      # is keyed by the decoded filesystem path — decode before the lookup.
      key = URI.decode(key)
      # prefix_root_relative_links runs before this pass and may already have
      # rewritten a root-relative src with the subpath, but the resize map is
      # keyed by bare root-relative paths — strip the base_path back off so the
      # lookup hits (then with_base_path re-adds it to the emitted candidates).
      bp = config.base_path
      key = key[bp.size..] if !bp.empty? && key.starts_with?("#{bp}/")

      widths = resize_map[key]?
      next tag unless widths
      next tag if widths.empty?

      # Prefix each candidate with the subpath (base_path) so responsive
      # images resolve on subpath deployments; the resize map stores bare
      # root-relative paths. Mirrors the resize_image() template helper.
      srcset = widths.to_a.sort_by { |(w, _)| w }.map { |(w, url)| "#{URI.encode_path(config.with_base_path(url))} #{w}w" }.join(", ")
      additions = %( srcset="#{srcset}")
      additions += %( sizes="100vw") unless tag =~ /\ssizes\s*=/
      tag.sub("<img", "<img#{additions}")
    end
  end

  private def generate_toc_html(headers : Array(Models::TocHeader)) : String
    return "" if headers.empty?

    String.build do |str|
      str << "<ul>"
      headers.each do |header|
        str << "<li><a href=\"#{header.permalink}\">#{header.title}</a>"
        unless header.children.empty?
          str << generate_toc_html(header.children)
        end
        str << "</li>"
      end
      str << "</ul>"
    end
  end

  # Convert TocHeader tree to Crinja-compatible array for toc_obj.headers.
  private def toc_headers_to_crinja(headers : Array(Models::TocHeader)) : Array(Crinja::Value)
    headers.map do |h|
      Crinja::Value.new({
        "level"     => Crinja::Value.new(h.level),
        "id"        => Crinja::Value.new(h.id),
        "title"     => Crinja::Value.new(h.title),
        "permalink" => Crinja::Value.new(h.permalink),
        "children"  => Crinja::Value.new(toc_headers_to_crinja(h.children)),
      })
    end
  end

  # Inject a dismissible error overlay into the HTML page for development feedback.
  # The overlay shows build warnings collected during rendering so developers
  # can spot template issues directly in the browser.
  private def inject_error_overlay(html : String, warnings : Array(String)) : String
    return html if warnings.empty?

    escaped_warnings = warnings.map { |w| HTML.escape(w) }
    list_items = escaped_warnings.map { |w|
      "<li style=\"margin-bottom:8px;line-height:1.5;\">#{w}</li>"
    }.join("\n")

    overlay = <<-OVERLAY
      <div id="hwaro-error-overlay" style="position:fixed;inset:0;z-index:99999;background:rgba(0,0,0,0.65);display:flex;align-items:center;justify-content:center;font-family:-apple-system,BlinkMacSystemFont,sans-serif;">
        <div style="background:#1e1e2e;color:#cdd6f4;border-radius:8px;padding:24px;max-width:720px;width:90%;max-height:80vh;overflow-y:auto;box-shadow:0 8px 32px rgba(0,0,0,0.4);">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px;">
            <h2 style="margin:0;color:#f38ba8;font-size:18px;">Build Warning</h2>
            <button onclick="document.getElementById('hwaro-error-overlay').remove()" style="background:none;border:none;color:#cdd6f4;font-size:24px;cursor:pointer;padding:0 4px;">&times;</button>
          </div>
          <ul style="margin:0;padding:0 0 0 20px;">
            #{list_items}
          </ul>
        </div>
      </div>
      OVERLAY

    # Inject before </body> if present, otherwise append
    if idx = html.rindex("</body>")
      html.insert(idx, overlay)
    else
      html + overlay
    end
  end
end
