require "file_utils"
require "json"
require "time"
require "../config/options/new_options"
require "../models/config"
require "../utils/errors"
require "../utils/logger"

module Hwaro
  module Services
    class Creator
      CONTENT_DIR    = "content"
      ARCHETYPES_DIR = "archetypes"

      # `<!-- hwaro: KEY[=VALUE], KEY[=VALUE] -->` directive that an
      # archetype can put on its very first line to declare metadata
      # hwaro should honour (and strip) before applying the template.
      # Keeping it an HTML comment means the archetype still parses
      # cleanly if hwaro isn't the one reading it.
      HWARO_DIRECTIVE_RE = /\A<!--\s*hwaro:\s*(.*?)\s*-->\s*\n?/

      # Keys accepted inside `<!-- hwaro: ... -->`. Anything else is
      # logged as a warning so typos (`bundlr=true`) surface instead of
      # silently becoming no-ops.
      KNOWN_DIRECTIVES = {"bundle"}

      # Validate a user-supplied `<path>` argument to `hwaro new` and
      # return a normalized form relative to `content/` (no prefix),
      # with `./`, `..`, and double-slash segments already collapsed.
      # The result is safe to pass straight into the existing Creator
      # resolution logic, which re-adds the `content/` prefix as needed.
      #
      # Raises `ArgumentError` when the input is empty, absolute, or
      # would resolve outside `content/`. Callers (the CLI) wrap the
      # failure in `HwaroError(HWARO_E_USAGE)` so the classified exit
      # code and `--json` payload match the rest of the tool.
      def self.validate_and_normalize_path!(raw : String) : String
        stripped = raw.strip
        if stripped.empty?
          raise ArgumentError.new("missing <path> argument")
        end

        if Path[stripped].absolute?
          raise ArgumentError.new(
            "Absolute path '#{raw}' is not allowed. " \
            "Paths are relative to #{CONTENT_DIR}/, e.g. 'posts/my-article.md'."
          )
        end

        full = Path[File.join(CONTENT_DIR, stripped)].normalize.to_s
        root_prefix = "#{CONTENT_DIR}#{File::SEPARATOR}"

        # The normalized path must sit strictly below content/ — equal
        # to the root is also a reject (no filename) and anything that
        # doesn't start with "content/" means `..` escaped the tree.
        unless full.starts_with?(root_prefix)
          raise ArgumentError.new(
            "Path '#{raw}' escapes the #{CONTENT_DIR}/ directory. " \
            "Use a path inside #{CONTENT_DIR}/, e.g. 'posts/my-article.md'."
          )
        end

        full[root_prefix.size..]
      end

      def run(options : Config::Options::NewOptions, config : Models::Config? = nil)
        path = options.path
        title = options.title || ""

        # --section overrides the base directory
        if section = resolve_section(options.section, path)
          if path && path.ends_with?(".md")
            filename = File.basename(path)
            full_path = File.join("content", section, filename)
          elsif path
            full_path = File.join("content", section, path)
            full_path += ".md" unless full_path.ends_with?(".md")
          else
            # No path given; title must be supplied via --title.
            full_path = nil
          end

          if full_path
            base_dir = File.dirname(full_path)
            if title.empty?
              filename_without_ext = File.basename(full_path, ".md")
              title = filename_without_ext.split("-").map(&.capitalize).join(" ")
            end
          else
            base_dir = File.join("content", section)
          end
        else
          # Determine if path is a file path or directory
          is_file_path = path && path.ends_with?(".md")
          # With explicit --no-bundle, a bare `<path>` (no .md) is treated as
          # a flat file slug (→ `content/<path>.md`) rather than as a section
          # directory that gets a `<title-slug>.md` appended. This avoids
          # `--no-bundle` producing a directory wrapper, which defeats the
          # whole point of the flag.
          is_no_bundle_flat = !path.nil? && options.bundle == false && !path.ends_with?(".md")

          if is_file_path && path
            # Extract directory and filename from path
            base_dir = File.dirname(path)
            base_dir = "content/drafts" if base_dir == "."

            # Extract title from filename if not provided
            if title.empty?
              filename_without_ext = File.basename(path, ".md")
              title = filename_without_ext.split("-").map(&.capitalize).join(" ")
            end

            filename = File.basename(path)
            if base_dir == "content/drafts"
              full_path = File.join(base_dir, filename)
            else
              full_path = path.starts_with?("content/") ? path : File.join("content", path)
            end
            base_dir = File.dirname(full_path)
          elsif is_no_bundle_flat && path
            normalized = path.starts_with?("content/") ? path : File.join("content", path)
            full_path = "#{normalized}.md"
            base_dir = File.dirname(full_path)
            if title.empty?
              filename_without_ext = File.basename(full_path, ".md")
              title = filename_without_ext.split("-").map(&.capitalize).join(" ")
            end
          else
            base_dir = path || "content/drafts"
            base_dir = "content/#{base_dir}" unless base_dir.starts_with?("content/")
            full_path = nil
          end
        end

        # Require `--title` (or an explicit `<path>.md`) whenever the title
        # cannot be inferred. The `new` command is flag-only: no interactive
        # prompts, so behavior is predictable in TTY, CI, and agent runs.
        if !full_path && title.empty?
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_USAGE,
            message: "missing --title (or <path>.md) argument",
            hint: "Pass --title, or give a path ending in .md (e.g. 'posts/my-post.md').",
          )
        end

        if !full_path
          if title.empty?
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_USAGE,
              message: "Title cannot be empty.",
              hint: "Pass a non-empty --title.",
            )
          end
          filename = title.downcase.gsub(/[^\p{L}\p{N}]+/, "-").strip("-") + ".md"
          full_path = File.join(base_dir, filename)
        end

        FileUtils.mkdir_p(base_dir) unless Dir.exists?(base_dir)

        # Draft: CLI flag > path-based detection
        is_draft = if options.draft.nil?
                     base_dir.includes?("drafts")
                   else
                     options.draft == true
                   end

        date = options.date || Time.local.to_s("%Y-%m-%d %H:%M:%S")
        tags = options.tags

        # Find archetype, extracting any hwaro directives (e.g. bundle=true)
        # before substitution so they don't end up in generated content.
        raw_archetype_content = find_archetype(options.archetype, full_path)
        archetype_content, archetype_directives =
          extract_directives(raw_archetype_content)

        content_new = (config || Models::Config.new).content_new

        # Resolve bundle mode: CLI > archetype directive > config default.
        # The CLI form is an explicit tri-state (`Bool?`) so `--no-bundle`
        # really overrides rather than defaulting back.
        bundle_mode = options.bundle
        bundle_mode = archetype_directives["bundle"]?.try { |v| v == "true" } if bundle_mode.nil?
        bundle_mode = content_new.bundle if bundle_mode.nil?

        # Reshape `<dir>/<name>.md` → `<dir>/<name>/index.md` when bundle
        # mode is active. Skipped if the path is already an `index.md`
        # or `_index.md` so repeated invocations (and accidental bundle
        # mode on section indices) don't create `foo/index/index.md`.
        #
        # Special case: when the user gave a dir-ish path like `bundle-post`
        # or `posts/bundled` (no .md, no --section), the earlier directory-
        # fallback already appended a `<title-slug>.md` to it, producing
        # `content/<path>/<slug>.md`. Treating that as a regular `.md` and
        # then bundle-wrapping would stack an extra directory
        # (`content/<path>/<slug>/index.md`). The user's intent with
        # `--bundle` is "the path IS the bundle directory", so collapse the
        # slug layer and land at `<path>/index.md`.
        path_is_dir_bundle = bundle_mode &&
                             options.section.nil? &&
                             options.path.try { |p| !p.ends_with?(".md") } == true

        if bundle_mode && !bundle_path?(full_path)
          candidate = if path_is_dir_bundle
                        File.join(File.dirname(full_path), "index.md")
                      else
                        bundle_path_for(full_path)
                      end
          if bundle_collides_with_sibling?(candidate)
            sibling = candidate.rchop("/index.md") + ".md"
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_IO,
              message: "Cannot create bundle at #{candidate}: single-file sibling already exists.",
              hint: "Remove #{sibling}, or omit --bundle to append to the existing file location.",
            )
          end
          full_path = candidate
          base_dir = File.dirname(full_path)
          FileUtils.mkdir_p(base_dir) unless Dir.exists?(base_dir)
        end

        content = if archetype_content
                    process_archetype(archetype_content, title, date, is_draft, tags)
                  else
                    generate_default_content(title, date, is_draft, tags, content_new)
                  end

        if File.exists?(full_path)
          raise Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_IO,
            message: "File already exists: #{full_path}",
            hint: "Pass a different <path>, or edit the existing file directly.",
          )
        end

        File.write(full_path, content)
        Logger.info "Created new content: #{full_path}"
        full_path
      end

      # Returns `{stripped_content, directives}`. When the archetype's first
      # line is `<!-- hwaro: k=v, k2=v2 -->`, that line is removed from the
      # content and the directives are returned as a hash. Shorthand keys
      # without `=VALUE` are treated as `k = "true"`. Unknown keys warn
      # (but don't fail) so typos surface instead of silently no-oping.
      private def extract_directives(content : String?) : {String?, Hash(String, String)}
        directives = {} of String => String
        return {nil, directives} unless content

        match = HWARO_DIRECTIVE_RE.match(content)
        return {content, directives} unless match

        match[1].split(",").each do |pair|
          k, _, v = pair.strip.partition("=")
          key = k.strip
          next if key.empty?
          unless KNOWN_DIRECTIVES.includes?(key)
            Logger.warn "Unknown hwaro directive '#{key}' in archetype; ignoring. Known keys: #{KNOWN_DIRECTIVES.to_a.sort.join(", ")}."
            next
          end
          directives[key] = v.strip.empty? ? "true" : v.strip
        end
        {content.sub(HWARO_DIRECTIVE_RE, ""), directives}
      end

      # `index.md` and `_index.md` are already "in bundle shape" — the
      # former is a page bundle's leaf file and the latter is a section
      # index. Wrapping either into `<name>/index.md` would be nonsense
      # (`posts/_index/index.md` creates a phantom section).
      private def bundle_path?(path : String) : Bool
        basename = File.basename(path)
        basename == "index.md" || basename == "_index.md"
      end

      private def bundle_path_for(path : String) : String
        base = File.basename(path, ".md")
        File.join(File.dirname(path), base, "index.md")
      end

      # True when switching `<name>.md` to `<name>/index.md` would
      # collide with an existing single-file sibling on disk. Both would
      # render to the same URL, so we refuse rather than silently create
      # a duplicate.
      private def bundle_collides_with_sibling?(full_path : String) : Bool
        sibling_md = full_path.rchop("/index.md") + ".md"
        File.exists?(sibling_md) && File.file?(sibling_md)
      end

      # Reconcile `-s section` with a path argument that already carries
      # a directory. Prior behaviour silently dropped the path's leading
      # directory and used the section — so `hwaro new posts/foo.md -s
      # docs` landed the file at `content/docs/foo.md` with no warning,
      # which made scripted flows and shell-completion surprise users.
      #
      # New behaviour: if the path's leading segment and the section
      # disagree, the path is authoritative (the user wrote the dir, so
      # respect it) and `--section` is dropped with a one-line warning.
      # When they match, or when the path lacks a directory entirely
      # (`-s docs foo.md`), the section is returned as-is.
      private def resolve_section(section : String?, path : String?) : String?
        return unless section
        return section unless path && path.includes?("/")

        first_segment = path.split("/").first
        return section if first_segment == section

        Logger.warn "  --section '#{section}' conflicts with directory '#{first_segment}/' in path '#{path}'; using the path and ignoring --section."
        nil
      end

      private def find_archetype(explicit_archetype : String?, path : String) : String?
        # 1. If explicit archetype is given, use it
        if explicit_archetype
          archetype_path = File.join(ARCHETYPES_DIR, "#{explicit_archetype}.md")
          if File.exists?(archetype_path)
            Logger.debug "Using archetype: #{archetype_path}"
            return File.read(archetype_path)
          else
            raise Hwaro::HwaroError.new(
              code: Hwaro::Errors::HWARO_E_USAGE,
              message: "Archetype not found: #{archetype_path}",
              hint: "Run 'hwaro new --list-archetypes' to see archetypes available in this project.",
            )
          end
        end

        # 2. Try to find archetype based on path
        # Extract relative path from content/ directory
        relative_path = path.lchop("content/")
        dir_path = File.dirname(relative_path)

        if dir_path != "."
          # Try progressively shorter paths
          # e.g., tools/develop/mytool.md -> try tools/develop.md, then tools.md
          parts = dir_path.split("/")

          # Try from most specific to least specific
          parts.size.downto(1) do |i|
            archetype_name = parts[0...i].join("/")
            archetype_path = File.join(ARCHETYPES_DIR, "#{archetype_name}.md")

            if File.exists?(archetype_path)
              Logger.debug "Using archetype: #{archetype_path}"
              return File.read(archetype_path)
            end
          end
        end

        # 3. Try default archetype
        default_archetype = File.join(ARCHETYPES_DIR, "default.md")
        if File.exists?(default_archetype)
          Logger.debug "Using default archetype: #{default_archetype}"
          return File.read(default_archetype)
        end

        # 4. No archetype found
        nil
      end

      private def process_archetype(archetype_content : String, title : String, date : String, is_draft : Bool, tags : Array(String)) : String
        tags_str = tags.empty? ? "[]" : "[#{tags.map { |t| "\"#{t.gsub("\"", "\\\"")}\"" }.join(", ")}]"
        content = archetype_content
          .gsub("{{ title }}", title)
          .gsub("{{title}}", title)
          .gsub("{{ date }}", date)
          .gsub("{{date}}", date)
          .gsub("{{ draft }}", is_draft.to_s)
          .gsub("{{draft}}", is_draft.to_s)
          .gsub("{{ tags }}", tags_str)
          .gsub("{{tags}}", tags_str)

        content
      end

      # Built-in scaffold used when no archetype matches. Format and extra
      # fields are driven by `[content.new]` in `config.toml` so the output
      # matches the rest of the site's conventions (TOML by default to align
      # with the shipped scaffolds).
      private def generate_default_content(
        title : String,
        date : String,
        is_draft : Bool,
        tags : Array(String),
        content_new : Models::ContentNewConfig,
      ) : String
        if content_new.json?
          build_json_front_matter(title, date, is_draft, tags, content_new.extra_fields)
        elsif content_new.yaml?
          build_yaml_front_matter(title, date, is_draft, tags, content_new.extra_fields)
        else
          build_toml_front_matter(title, date, is_draft, tags, content_new.extra_fields)
        end
      end

      private def build_toml_front_matter(title : String, date : String, is_draft : Bool, tags : Array(String), extra_fields : Array(String)) : String
        safe_title = escape_string(title)
        String.build do |str|
          str << "+++\n"
          str << "title = \"#{safe_title}\"\n"
          str << "date = \"#{date}\"\n"
          extra_fields.each { |f| str << "#{f} = \"\"\n" }
          str << "draft = true\n" if is_draft
          unless tags.empty?
            rendered = tags.map { |t| "\"#{escape_string(t)}\"" }.join(", ")
            str << "tags = [#{rendered}]\n"
          end
          str << "+++\n\n"
          str << "# #{title}\n"
        end
      end

      private def build_yaml_front_matter(title : String, date : String, is_draft : Bool, tags : Array(String), extra_fields : Array(String)) : String
        safe_title = escape_string(title)
        String.build do |str|
          str << "---\n"
          str << "title: \"#{safe_title}\"\n"
          str << "date: #{date}\n"
          extra_fields.each { |f| str << "#{f}: \"\"\n" }
          str << "draft: true\n" if is_draft
          unless tags.empty?
            str << "tags:\n"
            tags.each { |tag| str << "  - \"#{escape_string(tag)}\"\n" }
          end
          str << "---\n\n"
          str << "# #{title}\n"
        end
      end

      private def build_json_front_matter(title : String, date : String, is_draft : Bool, tags : Array(String), extra_fields : Array(String)) : String
        fields = {} of String => JSON::Any
        fields["title"] = JSON::Any.new(title)
        fields["date"] = JSON::Any.new(date)
        extra_fields.each { |f| fields[f] = JSON::Any.new("") }
        fields["draft"] = JSON::Any.new(true) if is_draft
        unless tags.empty?
          fields["tags"] = JSON::Any.new(tags.map { |t| JSON::Any.new(t) })
        end
        "#{JSON::Any.new(fields).to_pretty_json}\n\n# #{title}\n"
      end

      private def escape_string(value : String) : String
        value.gsub("\"", "\\\"").gsub("\n", " ")
      end
    end
  end
end
