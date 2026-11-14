require "./errors"
require "./logger"

module Hwaro
  module Utils
    # Reports the directories a source scan could not open (see
    # ext/dir_denied_record.cr): the globber skips them silently.
    module DeniedDirs
      # Warn once per unreadable directory under `root` (content, static, data).
      def self.warn(root : String) : Nil
        Dir.take_denied(root).each do |dir|
          Logger.warn "Cannot read directory #{dir} (permission denied); everything under it is skipped."
        end
      end

      # Fail the build when a directory under `root` is unreadable (templates:
      # a site without them is not a site with "no templates").
      def self.fail_if_any(root : String) : Nil
        return unless dir = Dir.take_denied(root).first?
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_IO,
          message: "Cannot read directory #{dir}: permission denied",
          hint: "Restore read and search permission on it (chmod u+rx #{dir}), or remove it."
        )
      end
    end
  end
end
