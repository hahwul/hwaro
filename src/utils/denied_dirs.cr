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

      # The source a template file that could not be read is loaded as: the
      # template set keeps the name, and compiling it raises (see
      # ext/dir_denied_record.cr). A control byte no template text carries.
      UNREADABLE_TEMPLATE = "\u{1}hwaro:unreadable-template\u{1}"

      def self.unreadable_template(path : String, reason : String) : String
        "#{UNREADABLE_TEMPLATE}#{path}\u{1}#{reason}"
      end

      def self.fail_if_unreadable_template(source : String) : Nil
        return unless source.starts_with?(UNREADABLE_TEMPLATE)
        path, _, reason = source.lchop(UNREADABLE_TEMPLATE).partition('\u{1}')
        raise Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_IO,
          message: "Cannot read template #{path}: #{reason}",
          hint: "Restore read permission on it (chmod u+r #{path}), or remove it."
        )
      end
    end
  end
end
