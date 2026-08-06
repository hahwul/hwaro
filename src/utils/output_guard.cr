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
        # Canonicalize once — the previous within_output_dir? + canonical
        # sequence expanded output_path twice (a getcwd syscall and several
        # Path allocations each), and this runs for every written file.
        canonical_output = canonical(output_path)
        if contains?(canonical(output_dir), canonical_output)
          canonical_output
        else
          Logger.warn "Skipping output outside output directory: #{output_path}"
          nil
        end
      end

      # Check if a path is within the output directory.
      #
      def within_output_dir?(output_path : String, output_dir : String) : Bool
        contains?(canonical(output_dir), canonical(output_path))
      end

      private def contains?(canonical_dir : String, canonical_output : String) : Bool
        return true if canonical_output == canonical_dir
        # Build the prefix from the canonical dir rather than always appending
        # a separator: at the filesystem root `canonical` legitimately returns
        # "/", and "/" + "/" would reintroduce the double-separator mismatch
        # this method exists to avoid.
        prefix = canonical_dir.ends_with?(File::SEPARATOR) ? canonical_dir : canonical_dir + File::SEPARATOR
        canonical_output.starts_with?(prefix)
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
