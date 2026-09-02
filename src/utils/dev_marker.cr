require "./logger"

# Dev-output marker (issue #756)
#
# `hwaro serve` derives its base_url from the bind address when --base-url is
# absent, so the pages it writes carry dev URLs (http://127.0.0.1:3000) and
# must never be deployed. Serve stamps the directory it builds into with this
# marker; `hwaro build` removes a marker left behind by a serve session (older
# versions shared the output dir), and `hwaro deploy` refuses a source
# directory that still carries one.
#
# A file is a marker by its CONTENT, never by its name alone: `static/.hwaro-dev`
# is a file a user may legitimately keep, and the build publishes it like any
# other hidden static file.

module Hwaro
  module Utils
    module DevMarker
      extend self

      FILENAME = ".hwaro-dev"

      # What the file says to whoever finds it in a directory listing or a
      # deploy artifact. The first line is the greppable contract — it is what
      # hwaro itself matches on (see `present?`), so CI can grep for it too.
      CONTENT =
        "This directory was written by `hwaro serve` and is not deployable.\n" \
        "Its pages carry the dev server's base_url (e.g. http://127.0.0.1:3000).\n" \
        "Run `hwaro build` and deploy that output instead.\n"

      # The greppable contract from CONTENT's first line, and the ONLY thing
      # that makes a `.hwaro-dev` file a marker.
      FIRST_LINE = CONTENT.lines.first

      def path(output_dir : String) : String
        File.join(output_dir, FILENAME)
      end

      # Content check, not just existence: `static/.hwaro-dev` is a legitimate
      # (if unusual) file for a user to keep, and the build publishes it like
      # any other hidden static file. Identifying the marker by FILENAME alone
      # meant the published copy made `hwaro deploy` refuse the whole tree
      # blaming a serve session that never ran, and the next build deleted the
      # user's file right after the static copy put it there.
      #
      # Only the FIRST line is compared: it is the documented contract, so a
      # marker written by an older (or newer) hwaro whose explanatory body has
      # drifted still counts. A user file whose first line happens to be
      # exactly that sentence is treated as a marker — it is announcing itself
      # as one, and that is the deliberate trade for not hashing whole bodies.
      # `fail_closed` is the deploy/build-warn default: an unreadable file
      # keeps its old existence-only meaning so we never ship (or silently
      # treat as production) output we cannot rule out as serve output.
      # Callers that would DELETE on a true result must pass `false` —
      # the same true would invert into "clearable".
      def present?(output_dir : String, *, fail_closed : Bool = true) : Bool
        marker = path(output_dir)
        return false unless File.exists?(marker)

        # Bounded read: a file under this name can be arbitrarily large and a
        # single line of it just as large, so never slurp it to compare one
        # sentence. The +2 leaves room for the delimiter (and a CRLF marker
        # written on Windows) so `chomp` can strip it.
        first = File.open(marker) { |io| io.gets(FIRST_LINE.bytesize + 2, chomp: true) }
        first == FIRST_LINE
      rescue File::NotFoundError
        # Deleted between the stat and the open — absent, not a marker.
        false
      rescue ex : IO::Error
        Logger.debug "Could not read dev marker #{marker}: #{ex.message}"
        fail_closed
      end

      def write(output_dir : String) : Nil
        File.write(path(output_dir), CONTENT)
      rescue ex : IO::Error
        # The marker is defense in depth, not a build product — a directory we
        # cannot stamp (read-only FS race, exotic mount) must not fail the
        # build that just succeeded in writing the site itself.
        Logger.debug "Could not write dev marker #{path(output_dir)}: #{ex.message}"
      end

      # Guarded by `present?` for the same reason it now checks content: the
      # build reads the marker BEFORE the static copy runs, so by the time it
      # removes one the file standing there may be the user's own
      # `static/.hwaro-dev`, freshly published over a genuine leftover.
      def remove(output_dir : String) : Nil
        marker = path(output_dir)
        File.delete(marker) if present?(output_dir)
      rescue ex : IO::Error
        Logger.debug "Could not remove dev marker #{path(output_dir)}: #{ex.message}"
      end
    end
  end
end
