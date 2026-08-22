# Content Lister Service
#
# This service provides functionality to list content files
# based on their publication status (all, drafts, published).

require "json"
require "yaml"
require "toml"
require "../utils/date_utils"
require "../utils/frontmatter_scanner"
require "../utils/logger"
require "../utils/text_utils"

module Hwaro
  module Services
    # Filesystem guard shared by the content-walking tool services (`tool
    # list` / `tool stats` here, plus `tool convert`, `tool validate` and
    # `tool unused-assets`). It lives beside the lister because that is the
    # walker the other services already build on.
    #
    # `Dir.glob` reports a symlink as an ordinary path, so a self-referential
    # link (`ln -s loop.md content/loop.md`), a mutually-pointing pair, or a
    # dangling link all come back looking like a normal file. Resolving one
    # fails with ELOOP/ENOENT, and `File.info?` — hence `File.directory?` —
    # RAISES `File::Error` on ELOOP, because it only swallows ENOENT/ENOTDIR.
    # `hwaro build` adopted an lstat-first guard for exactly this tree (see
    # `core/build/phases/read_content.cr`), but the tool commands still walked
    # it blind: `tool unused-assets` died with a raw filesystem error, and the
    # others turned every bad link into a read failure they reported as the
    # author's problem. Skip such entries the way the build does.
    #
    # Unlike the build this guard judges READABILITY only, never containment:
    # the build refuses a link resolving outside the project because it would
    # publish the target, whereas these commands merely read, and they take an
    # arbitrary `--content-dir` that need not sit under `Dir.current` — testing
    # containment against that root would skip every file the user asked about.
    module ContentWalk
      extend self

      # True when `path` is a regular file that can actually be opened.
      #
      # Anything that simply is not a file (a directory, or a FIFO/socket
      # whose `File.read` would block forever) is skipped without comment — it
      # was never content. A symlink we cannot follow is named in a single
      # warning instead, matching `Phases::Initialize#static_target_info`, so
      # a file missing from a listing or a validate summary is never silent.
      def readable_file?(path : String) : Bool
        # lstat never follows, so a cycle is an ordinary symlink entry here
        # instead of an ELOOP failure. For the common (non-symlink) case it is
        # also the only stat the walk needs.
        lstat = File.info?(path, follow_symlinks: false)
        return false if lstat.nil?
        return lstat.file? unless lstat.symlink?

        target = begin
          File.info?(path, follow_symlinks: true)
        rescue ex : File::Error
          Logger.warn "Skipping unresolvable symlink: #{path}"
          Logger.debug "Symlink stat failed: #{ex.message}"
          return false
        end

        if target.nil?
          Logger.warn "Skipping dangling symlink: #{path}"
          return false
        end

        target.file?
      end
    end

    # Filter type for listing content
    enum ContentFilter
      All
      Drafts
      Published
    end

    # Sort key for listing content. `Date` is the historical default
    # (newest first, path as tie-breaker); `Title` and `Path` sort
    # ascending. `--reverse` flips whichever order the key produced.
    enum ContentSort
      Date
      Title
      Path
    end

    # Publication state a file will have in a DEFAULT `hwaro build`.
    #
    # `draft` alone never described that: the build also drops future-dated
    # pages (`date` in the future) and expired ones (`expires` in the past),
    # and it honours a `draft` cascaded from an ancestor section. Reporting
    # all three as "published" made `tool list published` and `tool stats`
    # disagree with the site the very next build shipped.
    enum PublishState
      Published
      Draft
      Future
      Expired

      def label : String
        case self
        in Published then "published"
        in Draft     then "draft"
        in Future    then "future"
        in Expired   then "expired"
        end
      end
    end

    # Information about a content file
    struct ContentInfo
      include JSON::Serializable

      property path : String
      property title : String
      # Kept for compatibility with existing `--json` consumers: true when the
      # file is a draft (its own flag or one cascaded from a parent section).
      property draft : Bool

      @[JSON::Field(converter: Hwaro::Services::ContentInfo::TimeConverter, emit_null: true)]
      property date : Time?

      # `published` | `draft` | `future` | `expired` — what a default build
      # does with this file. Only `published` files are actually shipped.
      property status : String

      @[JSON::Field(converter: Hwaro::Services::ContentInfo::TimeConverter, emit_null: true)]
      property expires : Time?

      def initialize(
        @path : String,
        @title : String = "Untitled",
        @draft : Bool = false,
        @date : Time? = nil,
        @status : String = "published",
        @expires : Time? = nil,
      )
      end

      def initialize(
        @path : String,
        @title : String,
        @draft : Bool,
        @date : Time?,
        state : PublishState,
        @expires : Time? = nil,
      )
        @status = state.label
      end

      # Will a default `hwaro build` publish this file?
      def published? : Bool
        @status == PublishState::Published.label
      end

      module TimeConverter
        def self.to_json(value : Time?, json : JSON::Builder)
          if value
            json.string(value.to_s("%Y-%m-%dT%H:%M:%S%:z"))
          else
            json.null
          end
        end

        def self.from_json(pull : JSON::PullParser) : Time?
          str = pull.read_string_or_null
          str ? Time.parse_rfc3339(str) : nil
        end
      end
    end

    # Content Lister lists content files based on their status
    class ContentLister
      YAML_DELIMITER = "---"
      TOML_DELIMITER = "+++"

      # Column header labels — also used as the minimum column width so the
      # header row never glues two adjacent labels together when the data
      # values are shorter than the label itself (see column-width clamp in
      # `#display`). Keep these and the header `String.build` block in sync.
      HEADER_STATUS = "Status"
      HEADER_DATE   = "Date"
      HEADER_TITLE  = "Title"
      HEADER_PATH   = "Path"

      # Content directory path
      @content_dir : String
      @default_language : String? = nil

      def initialize(@content_dir : String = "content")
      end

      # List all content files
      def list_all : Array(ContentInfo)
        list_content(ContentFilter::All)
      end

      # List only draft content files
      def list_drafts : Array(ContentInfo)
        list_content(ContentFilter::Drafts)
      end

      # List only published content files
      def list_published : Array(ContentInfo)
        list_content(ContentFilter::Published)
      end

      # List content files based on filter. `sort` picks the ordering key,
      # `reverse` flips it, and `limit` caps the result AFTER sorting — so
      # `--sort date --limit 5` means "the 5 newest", not 5 arbitrary files.
      def list_content(
        filter : ContentFilter,
        sort : ContentSort = ContentSort::Date,
        reverse : Bool = false,
        limit : Int32? = nil,
      ) : Array(ContentInfo)
        unless Dir.exists?(@content_dir)
          Logger.error "Content directory '#{@content_dir}' not found"
          return [] of ContentInfo
        end

        files = find_content_files
        contents = [] of ContentInfo
        cascade = collect_cascade_drafts(files)
        now = Time.utc

        files.each do |file_path|
          info = parse_content_info(file_path, cascade, now)
          next unless info

          case filter
          when ContentFilter::All
            contents << info
          when ContentFilter::Drafts
            contents << info if info.draft
          when ContentFilter::Published
            # "Published" now means what the build ships, not merely
            # "not flagged draft": future and expired files are excluded.
            contents << info if info.published?
          end
        end

        case sort
        in ContentSort::Date
          # Sort by date (newest first), then by path
          contents.sort_by! do |info|
            {-(info.date.try(&.to_unix) || 0_i64), info.path}
          end
        in ContentSort::Title
          # Case-insensitive so "apple" and "Apple" don't split apart; path
          # keeps equal titles deterministic.
          contents.sort_by! { |info| {info.title.downcase, info.path} }
        in ContentSort::Path
          contents.sort_by!(&.path)
        end
        contents.reverse! if reverse
        contents = contents.first(limit) if limit

        contents
      end

      # Display content list in a formatted table
      def display(
        filter : ContentFilter,
        sort : ContentSort = ContentSort::Date,
        reverse : Bool = false,
        limit : Int32? = nil,
      )
        contents = list_content(filter, sort, reverse, limit)

        filter_name = case filter
                      when ContentFilter::Drafts    then "drafts"
                      when ContentFilter::Published then "published"
                      else                               "all"
                      end

        Logger.heading("list", "#{filter_name} · #{@content_dir}")

        if contents.empty?
          Logger.outcome("listed", "no content found", :info)
          return
        end

        Logger.info ""

        # Titles come from semi-trusted front matter, so strip control bytes
        # before they reach the terminal (a raw ANSI escape could repaint the
        # console, and it throws the column widths off either way).
        cells = contents.map do |info|
          {Utils::TextUtils.strip_control(info.title), Utils::TextUtils.strip_control(info.path)}
        end

        # Cap long cells so the table stays scannable; the header labels are
        # the minimum column widths (Logger::Table aligns to the widest cell).
        # Measured in terminal columns to match both `truncate` below and the
        # table's own padding.
        max_title_width = [[cells.max_of { |title, _| Utils::TextUtils.display_width(title) }, 30].min, HEADER_TITLE.size].max
        max_path_width = [[cells.max_of { |_, path| Utils::TextUtils.display_width(path) }, 40].min, HEADER_PATH.size].max

        table = Logger::Table.new([HEADER_STATUS, HEADER_DATE, HEADER_TITLE, HEADER_PATH])
        contents.each_with_index do |info, index|
          # `[future]` / `[expired]` are as unpublished as `[draft]` — a
          # default build ships none of them — so they get the same warn
          # colour rather than reading as published.
          status, status_role = case info.status
                                when "draft"   then {"[draft]", Logger::Role::Warn}
                                when "future"  then {"[future]", Logger::Role::Warn}
                                when "expired" then {"[expired]", Logger::Role::Warn}
                                else                {"[pub]", Logger::Role::Dim}
                                end
          title, path = cells[index]
          table.row(
            [
              status,
              info.date.try(&.to_s("%Y-%m-%d")) || "-",
              truncate(title, max_title_width),
              truncate(path, max_path_width),
            ],
            [status_role, Logger::Role::Dim, Logger::Role::Plain, Logger::Role::Dim]
          )
        end
        table.emit

        Logger.info ""
        Logger.outcome("listed", "#{contents.size} #{contents.size == 1 ? "file" : "files"}")
      end

      private def find_content_files : Array(String)
        files = [] of String

        # Unfollowable symlinks are dropped here (see `ContentWalk`) so one
        # bad link cannot turn a listing into a wall of "Failed to read
        # content file" warnings for files the build itself skips. `tool
        # stats` walks through this method too, so both stay consistent.
        Dir.glob(File.join(@content_dir, "**", "*.md")) do |file|
          files << file if ContentWalk.readable_file?(file)
        end

        Dir.glob(File.join(@content_dir, "**", "*.markdown")) do |file|
          files << file if ContentWalk.readable_file?(file)
        end

        files.sort
      end

      private def parse_content_info(
        file_path : String,
        cascade : Hash(Tuple(String, String), Bool) = {} of Tuple(String, String) => Bool,
        now : Time = Time.utc,
      ) : ContentInfo?
        # Match the build's frontmatter reader: a BOM'd file would otherwise
        # list as "Untitled" with no date while it builds correctly.
        content = Utils::TextUtils.strip_bom(File.read(file_path))

        title = "Untitled"
        draft = false
        # The build resolves a cascade against the DECLARED keys
        # (`front_matter_keys`), not against the parsed value: a page that
        # spells `draft = "true"` still shadows an ancestor's cascade even
        # though the value is not a boolean. Track presence separately so the
        # two agree.
        draft_declared = false
        date : Time? = nil
        expires : Time? = nil

        # Try TOML Front Matter (+++)
        if match = content.match(Utils::FrontmatterScanner::TOML_FRONTMATTER_RE)
          begin
            toml_fm = TOML.parse(match[1])
            title = toml_fm["title"]?.try(&.as_s?) || title
            if declared = toml_fm["draft"]?
              draft_declared = true
              draft = declared.as_bool? || false
            end
            date = toml_date(toml_fm["date"]?)
            expires = toml_date(toml_fm["expires"]?)
          rescue ex
            Logger.debug "TOML front matter parsing failed for #{file_path}: #{ex.message}"
          end
          # Try YAML Front Matter (---)
        elsif match = content.match(Utils::FrontmatterScanner::YAML_FRONTMATTER_RE)
          begin
            yaml_fm = YAML.parse(match[1])
            if yaml_fm.as_h?
              title = yaml_fm["title"]?.try(&.as_s?) || title
              if declared = yaml_fm["draft"]?
                draft_declared = true
                draft = declared.as_bool? || false
              end
              date = yaml_date(yaml_fm["date"]?)
              expires = yaml_date(yaml_fm["expires"]?)
            end
          rescue ex
            Logger.debug "YAML front matter parsing failed for #{file_path}: #{ex.message}"
          end
          # Try JSON Front Matter (balanced {...} at file start)
        elsif content.starts_with?('{') && (end_idx = Utils::FrontmatterScanner.find_json_end(content))
          begin
            # find_json_end returns a BYTE offset; byte_slice keeps multibyte
            # JSON frontmatter intact so title/date aren't silently lost.
            json_fm = JSON.parse(content.byte_slice(0, end_idx))
            if json_fm.as_h?
              title = json_fm["title"]?.try(&.as_s?) || title
              if declared = json_fm["draft"]?
                draft_declared = true
                draft = declared.as_bool? || false
              end
              date = parse_time(json_fm["date"]?.try(&.as_s?))
              expires = parse_time(json_fm["expires"]?.try(&.as_s?))
            end
          rescue ex
            Logger.debug "JSON front matter parsing failed for #{file_path}: #{ex.message}"
          end
        end

        is_draft = draft_declared ? draft : cascaded_draft?(file_path, cascade)
        state = publish_state(is_draft, date, expires, now)

        ContentInfo.new(
          path: file_path,
          title: title,
          draft: is_draft,
          date: date,
          state: state,
          expires: expires
        )
      rescue ex
        Logger.warn "Failed to read content file #{file_path}: #{ex.message}"
        nil
      end

      # Mirrors the build's filter ORDER (draft → expired → future) so the
      # reported reason matches the one `hwaro build` would report.
      private def publish_state(draft : Bool, date : Time?, expires : Time?, now : Time) : PublishState
        return PublishState::Draft if draft
        return PublishState::Expired if expires && expires <= now
        return PublishState::Future if date && date > now
        PublishState::Published
      end

      private def toml_date(value : TOML::Any?) : Time?
        return unless value
        raw = value.raw
        case raw
        when Time   then raw
        when String then parse_time(raw)
        end
      end

      private def yaml_date(value : YAML::Any?) : Time?
        return unless value
        if time_val = value.as_time?
          time_val
        elsif str_val = value.as_s?
          parse_time(str_val)
        end
      end

      # `[cascade] draft = true` on a section `_index` file marks every
      # descendant a draft, and the build drops them all. Collect those
      # declarations once per run, keyed by `{relative dir, language}` the
      # way `Phases::ParseContent#build_cascade_map` does.
      private def collect_cascade_drafts(files : Array(String)) : Hash(Tuple(String, String), Bool)
        map = {} of Tuple(String, String) => Bool

        files.each do |file_path|
          basename = File.basename(file_path)
          next unless basename.starts_with?("_index.")
          value = cascade_draft_value(file_path)
          next if value.nil?
          map[{relative_dir(file_path), language_token(basename)}] = value
        end

        map
      end

      # The `draft` entry of a section's `[cascade]` table, or nil when the
      # file declares no cascade (or no `draft` inside it).
      private def cascade_draft_value(file_path : String) : Bool?
        content = Utils::TextUtils.strip_bom(File.read(file_path))

        if match = content.match(Utils::FrontmatterScanner::TOML_FRONTMATTER_RE)
          TOML.parse(match[1])["cascade"]?.try(&.as_h?).try(&.["draft"]?).try(&.as_bool?)
        elsif match = content.match(Utils::FrontmatterScanner::YAML_FRONTMATTER_RE)
          YAML.parse(match[1]).as_h?.try(&.[YAML::Any.new("cascade")]?).try(&.as_h?)
            .try(&.[YAML::Any.new("draft")]?).try(&.as_bool?)
        elsif content.starts_with?('{') && (end_idx = Utils::FrontmatterScanner.find_json_end(content))
          JSON.parse(content.byte_slice(0, end_idx)).as_h?.try(&.["cascade"]?).try(&.as_h?)
            .try(&.["draft"]?).try(&.as_bool?)
        end
      rescue ex
        Logger.debug "Cascade parsing failed for #{file_path}: #{ex.message}"
        nil
      end

      # Walk the ancestor chain shallowest-first so the nearest section wins.
      # A section's own `_index` is NOT subject to its own cascade, and the
      # language must match exactly — `merged_cascade_for` keys strictly on
      # `{dir, language}`, so a `ko` page never inherits a default-language
      # section's cascade.
      private def cascaded_draft?(file_path : String, cascade : Hash(Tuple(String, String), Bool)) : Bool
        return false if cascade.empty?

        basename = File.basename(file_path)
        language = language_token(basename)
        dir = relative_dir(file_path)

        chain = [""] of String
        unless dir.empty?
          acc = ""
          dir.split('/').each do |part|
            acc = acc.empty? ? part : "#{acc}/#{part}"
            chain << acc
          end
        end
        # Cascade applies to descendants only.
        chain.pop if basename.starts_with?("_index.")

        result = false
        chain.each do |ancestor|
          # `if value = cascade[...]?` would drop a cascaded `draft = false`:
          # Crystal reads the retrieved `false` as a failed match, so a nested
          # section could never un-draft what an ancestor cascaded. The build
          # merges per ancestor, deeper wins — `false` included.
          next unless cascade.has_key?({ancestor, language})
          result = cascade[{ancestor, language}]
        end
        result
      end

      # Path of `file_path`'s directory relative to the content root, with
      # `""` for the root itself.
      private def relative_dir(file_path : String) : String
        relative = Path[file_path].relative_to?(Path[@content_dir]).try(&.to_s) || file_path
        dir = File.dirname(relative)
        dir == "." ? "" : dir
      end

      # The language suffix of a content filename (`about.ko.md` → `"ko"`),
      # or `""` for the default language. The build normalizes an absent
      # language to `config.default_language`, so a file that spells the
      # DEFAULT code out (`about.en.md` on an `en` site) has to normalize to
      # the same bucket as `about.md` — otherwise the two stop sharing a
      # section's cascade. The suffix test is shape-based: the build only
      # routes suffixes that look like a language code anyway.
      private def language_token(basename : String) : String
        stem = basename.sub(/\.(md|markdown)\z/, "")
        parts = stem.split('.')
        return "" if parts.size < 2
        candidate = parts.last
        return "" unless candidate.matches?(/\A[a-z]{2,3}(-[A-Za-z]{2,4})?\z/)
        candidate == default_language ? "" : candidate
      end

      # `default_language` from the project's `config.toml`, or `""` when
      # there is none to read. Parsed directly rather than through
      # `Models::Config` so the lister keeps taking nothing but a directory.
      private def default_language : String
        @default_language ||= read_default_language
      end

      private def read_default_language : String
        parent = File.dirname(@content_dir.rstrip(File::SEPARATOR))
        {File.join(parent, "config.toml"), "config.toml"}.each do |path|
          next unless File.exists?(path)
          begin
            return TOML.parse(Utils::TextUtils.strip_bom(File.read(path)))["default_language"]?.try(&.as_s?) || ""
          rescue
            return ""
          end
        end
        ""
      end

      private def parse_time(time_str : String?) : Time?
        return unless time_str
        Utils::DateUtils.parse_lenient(time_str)
      end

      # Cap a cell at `max_length` terminal COLUMNS. Measuring in codepoints
      # while the table pads by display width let a 30-codepoint CJK title
      # claim a 60-column column, undoing the alignment fix one step earlier.
      private def truncate(str : String, max_length : Int32) : String
        return str if Utils::TextUtils.display_width(str) <= max_length

        budget = max_length - 3
        kept = String.build do |io|
          used = 0
          str.each_char do |c|
            w = Utils::TextUtils.display_width(c.to_s)
            break if used + w > budget
            io << c
            used += w
          end
        end
        "#{kept}..."
      end
    end
  end
end
