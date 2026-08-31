require "./logger"

# Dev-output marker (issue #756)
#
# `hwaro serve` derives its base_url from the bind address when --base-url is
# absent, so the pages it writes carry dev URLs (http://127.0.0.1:3000) and
# must never be deployed. Serve stamps the directory it builds into with this
# marker; `hwaro build` removes a marker left behind by a serve session (older
# versions shared the output dir), and `hwaro deploy` refuses a source
# directory that still carries one.

module Hwaro
  module Utils
    module DevMarker
      extend self

      FILENAME = ".hwaro-dev"

      # What the file says to whoever finds it in a directory listing or a
      # deploy artifact. The first line is the greppable contract; CI can
      # `test -f` the filename alone.
      CONTENT = <<-TEXT
      This directory was written by `hwaro serve` and is not deployable.
      Its pages carry the dev server's base_url (e.g. http://127.0.0.1:3000).
      Run `hwaro build` and deploy that output instead.

      TEXT

      def path(output_dir : String) : String
        File.join(output_dir, FILENAME)
      end

      def present?(output_dir : String) : Bool
        File.exists?(path(output_dir))
      end

      def write(output_dir : String) : Nil
        File.write(path(output_dir), CONTENT)
      rescue ex : IO::Error
        # The marker is defense in depth, not a build product — a directory we
        # cannot stamp (read-only FS race, exotic mount) must not fail the
        # build that just succeeded in writing the site itself.
        Logger.debug "Could not write dev marker #{path(output_dir)}: #{ex.message}"
      end

      def remove(output_dir : String) : Nil
        marker = path(output_dir)
        File.delete(marker) if File.exists?(marker)
      rescue ex : IO::Error
        Logger.debug "Could not remove dev marker #{path(output_dir)}: #{ex.message}"
      end
    end
  end
end
