# Dev server — ChangeSet, the classified set of watched-file changes and the rebuild strategy it implies.
#
# Split out of server.cr, which keeps the require order, the Server ivars
# and the boot sequence. Parts only define or reopen types: no requires, no
# load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    # Categorised set of file-system changes detected by the watcher.
    #
    # Changes are split into five buckets so the server can pick the
    # cheapest rebuild strategy.
    struct ChangeSet
      # Content files (.md under content/) that were *modified* (not added/deleted)
      getter modified_content : Array(String)
      # Non-Markdown files under content/ (images and other assets published
      # via `[content.files] allow_extensions`) that were *modified*. These
      # are not pages — they're copied 1:1 to the output dir on rebuild, so
      # they can't ride the incremental page pipeline.
      getter modified_content_files : Array(String)
      # Template files that were *modified*
      getter modified_templates : Array(String)
      # Static files that were *modified*
      getter modified_static : Array(String)
      # Data / i18n files (data/**, i18n/**) that were *modified*. Templates
      # read `site.data` and translations feed every localized string, so any
      # page may depend on these — a change here forces a full rebuild.
      getter modified_data : Array(String)
      # Files that were added (new) – present in current scan but not previous
      getter added_files : Array(String)
      # Files that were removed – present in previous scan but not current
      getter removed_files : Array(String)
      # Whether config.toml itself changed
      getter config_changed : Bool

      def initialize(
        @modified_content : Array(String),
        @modified_templates : Array(String),
        @modified_static : Array(String),
        @added_files : Array(String),
        @removed_files : Array(String),
        @config_changed : Bool,
        @modified_content_files : Array(String) = [] of String,
        @modified_data : Array(String) = [] of String,
      )
      end

      # True when the change set is empty (nothing actually changed)
      def empty? : Bool
        @modified_content.empty? &&
          @modified_content_files.empty? &&
          @modified_templates.empty? &&
          @modified_static.empty? &&
          @modified_data.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # True when a full rebuild is unavoidable:
      # config changed, data/i18n changed (any page may read them), or files
      # were added / deleted (which affects section lists, navigation,
      # taxonomy indices, etc.)
      def needs_full_rebuild? : Bool
        @config_changed || !@added_files.empty? || !@removed_files.empty? ||
          !@modified_data.empty?
      end

      # True when only template files were modified (no content / static / structural changes)
      def templates_only? : Bool
        !@modified_templates.empty? &&
          @modified_content.empty? &&
          @modified_content_files.empty? &&
          @modified_static.empty? &&
          @modified_data.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # True when only static files were modified
      def static_only? : Bool
        !@modified_static.empty? &&
          @modified_content.empty? &&
          @modified_content_files.empty? &&
          @modified_templates.empty? &&
          @modified_data.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # True when only non-Markdown content files were modified — just
      # republish them, no markdown re-parsing, no template re-render.
      def content_files_only? : Bool
        !@modified_content_files.empty? &&
          @modified_content.empty? &&
          @modified_templates.empty? &&
          @modified_static.empty? &&
          @modified_data.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # True when content and templates changed together (no structural changes)
      def content_and_template_only? : Bool
        !@modified_content.empty? &&
          !@modified_templates.empty? &&
          @modified_data.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # True when content was modified (possibly alongside static changes)
      # but no structural / config / template changes occurred.
      def content_incremental? : Bool
        !@modified_content.empty? &&
          @modified_templates.empty? &&
          @modified_data.empty? &&
          @added_files.empty? &&
          @removed_files.empty? &&
          !@config_changed
      end

      # Merge another ChangeSet into this one, combining all buckets.
      # Used during debounce to batch rapid successive changes.
      #
      # Order-aware semantics (self happens first, then other):
      # - add→remove cancels out (file created then deleted = no-op)
      # - remove→add keeps the add (file deleted then recreated = net add,
      #   e.g. atomic save via delete+move)
      def merge(other : ChangeSet) : ChangeSet
        self_only_added = @added_files - other.removed_files
        self_only_removed = @removed_files - other.added_files
        other_only_added = other.added_files - @removed_files
        other_only_removed = other.removed_files - @added_files

        # remove→add: file existed, was removed in self, re-added in other.
        # Treat as net add so we don't skip a rebuild.
        revived = @removed_files & other.added_files

        net_added = (self_only_added + other_only_added + revived).uniq
        net_removed = (self_only_removed + other_only_removed).uniq

        ChangeSet.new(
          modified_content: (@modified_content + other.modified_content).uniq,
          modified_content_files: (@modified_content_files + other.modified_content_files).uniq,
          modified_templates: (@modified_templates + other.modified_templates).uniq,
          modified_static: (@modified_static + other.modified_static).uniq,
          modified_data: (@modified_data + other.modified_data).uniq,
          added_files: net_added,
          removed_files: net_removed,
          config_changed: @config_changed || other.config_changed,
        )
      end

      # Determine the optimal rebuild strategy for this changeset.
      #
      # The `*_only?` predicates above are mutually exclusive by bucket
      # emptiness, so a changeset mixing two non-content buckets —
      # templates+static, templates+content-asset, static+content-asset —
      # matched none of them and fell through to `else`, taking a FULL
      # rebuild. That was wasted work (nothing structural changed, and each
      # of those buckets has its own cheap path) and, worse, the #760 loop:
      # a full rebuild is the ONLY strategy that re-runs `build.hooks.pre`,
      # so a pre hook rewriting one templates/ and one static/ file
      # byte-identically on every run retriggered itself forever — the #755
      # mechanism, outside the two hashed buckets.
      #
      # The two trailing branches route those mixed sets to the cheapest
      # strategy their heaviest bucket needs. Nothing is left stale:
      # apply_changeset already copies static files and content assets
      # alongside every non-full strategy.
      def rebuild_strategy : Symbol
        if needs_full_rebuild?
          :full
        elsif templates_only?
          :templates
        elsif content_and_template_only?
          :content_and_template
        elsif content_incremental?
          :incremental
        elsif static_only?
          :static
        elsif content_files_only?
          :content_files
        elsif !@modified_templates.empty?
          # Templates plus static files and/or content assets. Markdown is
          # necessarily empty here — content alongside templates already
          # matched content_and_template_only?.
          :templates
        elsif !@modified_static.empty?
          # Static files plus content assets.
          :static
        else
          :full
        end
      end

      # Human-readable description of the change for logging. The trailing
      # noun is pluralized by the total file count; a config change is named
      # separately since it is one specific file, not a category count.
      def description : String
        parts = [] of String
        total = 0
        {
          "content"       => @modified_content,
          "content-asset" => @modified_content_files,
          "template"      => @modified_templates,
          "static"        => @modified_static,
          "data"          => @modified_data,
          "added"         => @added_files,
          "removed"       => @removed_files,
        }.each do |label, list|
          next if list.empty?
          parts << "#{list.size} #{label}"
          total += list.size
        end
        desc = parts.empty? ? "" : "#{parts.join(", ")} #{total == 1 ? "file" : "files"}"
        if @config_changed
          desc = desc.empty? ? "config" : "#{desc}, config"
        end
        desc
      end

      # What the watch timeline prints: the path itself when exactly one file
      # changed (the common save-one-file loop), the category summary above
      # otherwise.
      def display : String
        return "config.toml" if @config_changed && all_changed_files.empty?
        files = all_changed_files
        files.size == 1 && !@config_changed ? files.first : description
      end

      private def all_changed_files : Array(String)
        @modified_content + @modified_content_files + @modified_templates +
          @modified_static + @modified_data + @added_files + @removed_files
      end
    end
  end
end
