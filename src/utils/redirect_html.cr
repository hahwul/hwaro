# Redirect HTML generation utilities
#
# Provides methods to generate HTML redirect pages with proper
# meta refresh tags, canonical links, and JavaScript fallbacks.

require "html"

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
        html_escaped_url = TextUtils.escape_xml(url)
        # For JavaScript context: escape backslashes, quotes, newlines, and </script>
        js_escaped_url = url
          .gsub("\\", "\\\\")
          .gsub("\"", "\\\"")
          .gsub("\n", "\\n")
          .gsub("\r", "\\r")
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
