# Redirect HTML generation utilities
#
# Provides methods to generate HTML redirect pages with proper
# meta refresh tags, canonical links, and JavaScript fallbacks.

require "html"
require "./logger"
require "../content/processors/inline_markdown"

module Hwaro
  module Utils
    module RedirectHtml
      extend self

      # Generate a full redirect page with meta refresh, canonical link,
      # and JavaScript fallback.
      #
      # Example:
      #   full_redirect("/blog/new-post/")
      #   # => "<!DOCTYPE html>..."
      #
      def full_redirect(url : String) : String
        # `redirect_to` is read verbatim from page front matter (semi-trusted:
        # a docs/blog PR contributor controls it). HTML-escaping alone keeps a
        # `javascript:` scheme intact, so the emitted `<a href>` would execute
        # script on click — stored XSS in published output. Reject dangerous
        # schemes outright and emit an inert notice instead of a live link.
        unless Hwaro::Content::Processors::InlineMarkdown.safe_url?(url)
          Logger.warn "Refusing redirect to unsafe URL scheme: #{url.inspect}"
          return blocked_redirect(url)
        end

        html_escaped_url = TextUtils.escape_xml(url)
        # For JavaScript context: escape backslashes, quotes, newlines, and </script>
        js_escaped_url = url
          .gsub("\\", "\\\\")
          .gsub("\"", "\\\"")
          .gsub("\n", "\\n")
          .gsub("\r", "\\r")
          .gsub("\u2028", "\\u2028") # JS line terminators: would otherwise
          .gsub("\u2029", "\\u2029") # break the string literal on pre-ES2019 engines
          .gsub("</", "<\\/")

        <<-HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="utf-8">
            <meta http-equiv="refresh" content="0; url=#{html_escaped_url}">
            <link rel="canonical" href="#{html_escaped_url}">
            <title>Redirecting...</title>
          </head>
          <body>
            <p>Redirecting to <a href="#{html_escaped_url}">#{html_escaped_url}</a>...</p>
            <script>window.location.href = "#{js_escaped_url}";</script>
          </body>
          </html>
          HTML
      end

      # Inert page shown when `redirect_to` carries an unsafe URL scheme. No
      # meta-refresh, no `window.location`, no clickable link — just escaped
      # text so the dangerous URL can never execute or auto-navigate.
      private def blocked_redirect(url : String) : String
        escaped_url = TextUtils.escape_xml(url)
        <<-HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="utf-8">
            <title>Redirect blocked</title>
          </head>
          <body>
            <p>This page was configured to redirect to a URL with an unsupported scheme, so the redirect was blocked: #{escaped_url}</p>
          </body>
          </html>
          HTML
      end

      # Generate a simple redirect page with meta refresh only.
      # Used for alias redirects where a simpler page suffices.
      #
      # Example:
      #   simple_redirect("/blog/new-post/")
      #   # => "<!DOCTYPE html>..."
      #
      def simple_redirect(url : String) : String
        escaped_url = HTML.escape(url)
        <<-HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta http-equiv="refresh" content="0; url=#{escaped_url}" />
            <title>Redirecting to #{escaped_url}</title>
          </head>
          <body>
            <p>Redirecting to <a href="#{escaped_url}">#{escaped_url}</a>.</p>
          </body>
          </html>
          HTML
      end
    end
  end
end
