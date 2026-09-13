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

      # Percent-encoded NUL. Deleting it (what the shared `sanitize_path` does)
      # made `/index%00.html` serve the real homepage with a 200, while the
      # StaticFileHandler sitting in the same chain answers a decoded NUL with
      # 400 — an inconsistency inside one server. Fail closed instead.
      ENCODED_NULL = /%00/i

      # A segment that is nothing but dots and spaces. `..` is the parent link;
      # `...`, `".. "` and `". "` are included because Windows strips BOTH
      # trailing dots and trailing spaces from a path component, which can
      # collapse them onto one that traverses. Same predicate the shared
      # `PathUtils.sanitize_path` uses, so the two cannot drift.
      #
      # Deliberately NOT "contains `..`": after a single decode only such a
      # segment can traverse, while `lib.v1..2.js` or a slug like `a..b` are
      # ordinary filenames that a static host serves. Rejecting those would
      # reintroduce — in the opposite direction — the dev/prod divergence this
      # resolver exists to remove.
      def dots_only?(segment : String) : Bool
        segment.rstrip(". ").empty?
      end

      # Resolve a request path to a path relative to the output root, or nil
      # when the request must not be served from disk at all. An empty string
      # means "the output root itself" (e.g. `/`), which callers handle
      # separately from nil.
      # True for request shapes no static host serves: a backslash separator,
      # an encoded `/` or `\`, or a NUL in any form. Declining them in our own
      # handlers is not enough — `HTTP::StaticFileHandler` decodes once too and
      # would happily resolve `/%2Fguide%2Findex.html` to the real page — so
      # `UnservablePathHandler` turns this predicate into an actual 404 before
      # the request can reach it.
      def unservable?(path : String) : Bool
        # MUST come first: the regexes below run PCRE2 over the raw request
        # bytes, and invalid UTF-8 makes that raise `ArgumentError` straight
        # out of the handler — a 500 for a request a static host answers with
        # a 404. Invalid bytes are unservable by definition.
        return true unless path.valid_encoding?

        return true if path.includes?('\\') ||
                       path.includes?(Char::ZERO) ||
                       ENCODED_SEPARATOR.matches?(path) ||
                       ENCODED_NULL.matches?(path)

        # Percent-encoded invalid UTF-8 (`/%c0%ae%c0%ae/`, `/%ff`) is valid
        # ASCII on the wire and only becomes invalid after decoding, so the
        # check above cannot see it. Nothing downstream can serve such a path
        # — `safe_relative` refuses it — but `HTTP::StaticFileHandler` decodes
        # it, canonicalises it, and re-encodes the result, which turns every
        # undecodable byte into U+FFFD: `/%c0%ae%c0%ae/` was answered with a
        # 302 to `/%EF%BF%BD%EF%BF%BD%EF%BF%BD%EF%BF%BD/index.html`. A static
        # host 404s the request; so do we. Guarded on `%` so the ordinary path
        # pays no decode.
        return true if path.includes?('%') && !URI.decode(path).valid_encoding?

        false
      end

      def safe_relative(path : String) : String?
        return if unservable?(path)

        decoded = URI.decode(path)
        # Percent-encoded invalid UTF-8 (`%c0%ae`, `%ff`) only becomes invalid
        # after decoding, and every operation below would raise on it.
        return unless decoded.valid_encoding?

        segments = decoded.split('/').reject { |segment| segment.empty? || segment == "." }
        # Refuse any dots-and-spaces segment so nothing walks out of the
        # output directory (see dots_only?).
        return if segments.any? { |segment| dots_only?(segment) }

        segments.join("/")
      end

      # The canonical form of `path` when it is not already canonical, or nil
      # when nothing should be redirected.
      #
      # Mirrors `HTTP::StaticFileHandler`'s own test exactly — decode once,
      # `Path.posix(...).expand("/")`, compare as `Path` — so a pre-empt built
      # on this fires when and only when stdlib would have redirected, and
      # lands on the same target (`Path#expand` keeps a trailing slash, so a
      # directory URL stays a directory URL). The result is re-encoded because
      # the comparison runs on decoded bytes.
      #
      # Handlers pre-empt stdlib rather than letting it answer because a
      # redirect it emits reflects whatever the chain did to `request.path`
      # along the way — `IndexRewriteHandler`'s `/` → `/index.html` rewrite
      # leaked into it — and because `Response#redirect` closes the response,
      # so no handler above can correct the `Location` afterwards.
      def canonical_target(path : String) : String?
        # Never canonicalise a path the server refuses to serve: an
        # unservable path must be 404'd, not redirected, and `Path.posix`
        # raises on a NUL.
        return if unservable?(path)

        decoded = URI.decode(path)
        return unless decoded.valid_encoding?

        request_path = Path.posix(decoded)
        expanded = request_path.expand("/")
        return if request_path == expanded
        URI.encode_path(expanded.to_s)
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
