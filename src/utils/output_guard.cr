# Output directory guard utilities
#
# Provides path traversal safety checks for file output operations.
# Ensures generated files never escape the designated output directory.

module Hwaro
  module Utils
    module OutputGuard
      extend self

      # Verify that the given output path is within the output directory.
      # Returns the output_path if safe, or a fallback path and logs a warning.
      #
      # Example:
      #   safe_path("public/../etc/passwd", "public")  # => "public/index.html" (with warning)
      #   safe_path("public/blog/index.html", "public") # => "public/blog/index.html"
      #
      def safe_output_path(output_path : String, output_dir : String) : String?
        canonical_output = File.expand_path(output_path)
        canonical_output_dir = File.expand_path(output_dir)
        if canonical_output == canonical_output_dir || canonical_output.starts_with?(canonical_output_dir + "/")
          canonical_output
        else
          Logger.warn "  [WARN] Skipping output outside output directory: #{output_path}"
          nil
        end
      end

      # Check if a path is within the output directory.
      #
      def within_output_dir?(output_path : String, output_dir : String) : Bool
        canonical_output = File.expand_path(output_path)
        canonical_output_dir = File.expand_path(output_dir)
        canonical_output == canonical_output_dir || canonical_output.starts_with?(canonical_output_dir + "/")
      end
    end
  end
end
