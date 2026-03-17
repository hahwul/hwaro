# Phase: ReadContent — content path collection
#
# Handles collecting content file paths from the content/ directory
# without parsing them. Creates Page and Section objects and collects
# raw files (JSON, XML) for later processing.

module Hwaro::Core::Build::Phases::ReadContent
  LANGUAGE_FILENAME_PATTERN = /^(.+)\.([a-z]{2,3})\.md$/

  private def execute_read_content_phase(ctx : Lifecycle::BuildContext, profiler : Profiler) : Lifecycle::HookResult
    profiler.start_phase("ReadContent")
    result = @lifecycle.run_phase(Lifecycle::Phase::ReadContent, ctx) do
      collect_content_paths(ctx, ctx.options.drafts)
      Logger.info "  Found #{ctx.all_pages.size} pages."
    end
    profiler.end_phase
    result
  end

  # Collect content file paths without parsing (single directory traversal)
  private def collect_content_paths(ctx : Lifecycle::BuildContext, include_drafts : Bool)
    config = ctx.config
    content_files_enabled = config.try(&.content_files.enabled?) || false
    seen_raw = Set(String).new

    # Single pass over content directory for both markdown and raw files
    Dir.glob("content/**/*") do |file_path|
      next if File.directory?(file_path)
      relative_path = Path[file_path].relative_to("content").to_s
      ext = Path[file_path].extension.downcase

      if ext == ".md"
        # Process markdown file
        basename = Path[relative_path].basename
        language = extract_language_from_filename(basename, config)

        clean_basename = if language
                           basename.sub(/\.#{language}\.md$/, ".md")
                         else
                           basename
                         end

        is_section_index = clean_basename == "_index.md"
        is_index = clean_basename == "index.md" || is_section_index

        if is_section_index
          page = Models::Section.new(relative_path)
          ctx.sections << page
        else
          page = Models::Page.new(relative_path)
          ctx.pages << page
        end

        path_parts = Path[relative_path].parts
        if is_section_index
          page.section = path_parts.size > 1 ? path_parts[0..-2].join("/") : ""
        elsif is_index
          page.section = path_parts.size > 2 ? path_parts[0..-3].join("/") : ""
        else
          page.section = path_parts.size > 1 ? path_parts[0..-2].join("/") : ""
        end
        page.is_index = is_index
        page.language = language
      else
        # Collect raw files (JSON, XML) and content files
        next if seen_raw.includes?(relative_path)
        is_raw = ext == ".json" || ext == ".xml"
        is_content_file = content_files_enabled && config && Content::Processors::ContentFiles.publish?(relative_path, config)

        if is_raw || is_content_file
          ctx.raw_files << Lifecycle::RawFile.new(file_path, relative_path)
          seen_raw << relative_path
        end
      end
    end
  end

  # Extract language code from filename if it matches configured languages
  private def extract_language_from_filename(basename : String, config : Models::Config?) : String?
    return nil unless config
    return nil unless config.multilingual?

    # Match pattern: filename.lang.md (e.g., "about.ko.md" -> "ko", "_index.ko.md" -> "ko")
    if match = basename.match(LANGUAGE_FILENAME_PATTERN)
      lang_code = match[2]
      return lang_code if config.languages.has_key?(lang_code) || lang_code == config.default_language
    end

    nil
  end
end
