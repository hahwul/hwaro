require "uri"

module Hwaro
  module Services
    # Request-path resolution for the dev server's own handlers.
    #
    # `Utils::PathUtils.sanitize_path` is deliberately lenient — it decodes
    # until stable and treats `\` as a separator — because it also guards
    # config-supplied paths. Using it to *route* HTTP requests made the dev
    # server answer 200 for URLs that every static host 404s
    # (`/guide%5Cindex.html`, `/%2Fguide%2Findex.html`, and their
    # double-encoded forms), so a broken link worked locally and broke after
    # deploy.
    #
    # This resolver is strict instead: one decode pass, `/` is the only
    # separator, and encoded separators are refused outright. Legitimately
    # percent-encoded paths (`/%ED%95%9C%EA%B8%80/` for `/한글/`) still
    # resolve, in both raw-UTF-8 and encoded form.
    module DevPath
      extend self

      # `%2f` / `%5c` in any casing. Double-encoded forms (`%252f`) survive the
      # single decode as a literal `%2f` inside one segment, which then simply
      # doesn't exist on disk — no separate rule needed.
      ENCODED_SEPARATOR = /%(?:2f|5c)/i

      # A segment made of nothing but dots. `..` is the parent link; `...` and
      # `....` are included because Windows strips trailing dots from a path
      # component, which can collapse them onto a shorter one.
      #
      # Deliberately NOT "contains `..`": after a single decode only an
      # all-dots segment can traverse, while `lib.v1..2.js` or a slug like
      # `a..b` are ordinary filenames that a static host serves. Rejecting
      # those would reintroduce — in the opposite direction — the dev/prod
      # divergence this resolver exists to remove.
      DOTS_ONLY = /\A\.+\z/

      # Resolve a request path to a path relative to the output root, or nil
      # when the request must not be served from disk at all. An empty string
      # means "the output root itself" (e.g. `/`), which callers handle
      # separately from nil.
      def safe_relative(path : String) : String?
        return if path.includes?('\\')
        return if ENCODED_SEPARATOR.matches?(path)

        # NUL bytes never reach the filesystem.
        decoded = URI.decode(path).delete(Char::ZERO)
        segments = decoded.split('/').reject { |segment| segment.empty? || segment == "." }
        # Refuse any all-dots segment so nothing walks out of the output
        # directory (see DOTS_ONLY).
        return if segments.any? { |segment| DOTS_ONLY.matches?(segment) }

        segments.join("/")
      end

      # Percent-encode a resolved relative path back into a URI reference.
      # `safe_relative` hands back decoded bytes, so a redirect built straight
      # from it would put a raw space (or raw UTF-8) into `Location:`.
      def encode_relative(relative : String) : String
        return relative if relative.empty?
        relative.split('/').map { |segment| URI.encode_path_segment(segment) }.join("/")
      end
    end
  end
end
