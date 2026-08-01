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
        if within_output_dir?(output_path, output_dir)
          canonical(output_path)
        else
          Logger.warn "Skipping output outside output directory: #{output_path}"
          nil
        end
      end

      # Check if a path is within the output directory.
      #
      def within_output_dir?(output_path : String, output_dir : String) : Bool
        canonical_output = canonical(output_path)
        canonical_output_dir = canonical(output_dir)
        canonical_output == canonical_output_dir ||
          canonical_output.starts_with?(canonical_output_dir + File::SEPARATOR)
      end

      # Absolute, comparison-ready form of `path`.
      #
      # `File.expand_path` resolves `.`/`..` segments but PRESERVES a trailing
      # separator, so `expand_path("public/")` is `"…/public/"` while
      # `expand_path("public/index.html")` is `"…/public/index.html"`. The
      # containment test then compared against `"…/public//"` and rejected
      # every page — a `-o public/` build (what shell directory completion
      # types for you) silently published nothing. Dropping trailing
      # separators makes `public/` and `public` the same directory again.
      private def canonical(path : String) : String
        expanded = File.expand_path(path)
        return expanded if expanded == File::SEPARATOR_STRING
        expanded.rstrip(File::SEPARATOR)
      end
    end
  end
end
