require "./dev_marker"
require "./logger"

# Build-output oracle (issue #761)
#
# `hwaro doctor` and `hwaro tool check-links` run OUTSIDE the build, so the
# only evidence they have for a path no source file explains — compiled Sass,
# resized/LQIP image variants, `[content.files]` output, generated routes — is
# a previous build's `[build] output_dir`.
#
# Since #758 `hwaro serve` builds into `.hwaro/serve/` and never touches that
# directory, so a serve-only workflow validates against a tree that is either
# ABSENT (every pipeline-emitted path reads as missing — false positives) or
# FROZEN at an old `hwaro build` (paths that no longer exist still validate —
# false negatives). Neither tool used to notice, and neither said so.
#
# This wraps the probe so both consult the tree the same way:
#
#   * a tree that is absent, empty, or carries the `.hwaro-dev` marker is
#     never used as evidence (the marker rule `hwaro deploy` already applies),
#   * a tree that WAS used as evidence and predates the sources says so,
#   * every case carries a one-sentence hint naming the fix.
#
# Staleness is computed lazily and only when the tree actually decided
# something, so a tool that never consults it pays nothing.
module Hwaro
  module Utils
    module BuildOutput
      extend self

      # Where `hwaro serve` builds (mirrors `ServeOptions::DEV_OUTPUT_DIR`).
      # Named in hints so a serve-only workflow understands why its
      # `output_dir` is empty. Duplicated rather than required so this util
      # stays free of CLI dependencies.
      SERVE_OUTPUT_DIR = ".hwaro/serve"

      # Source trees whose newest mtime a trustworthy build output must
      # postdate. Callers pass their own resolved paths; this is the
      # convention-named fallback.
      DEFAULT_SOURCES = %w[config.toml content templates static data themes sass assets]

      # Upper bound on entries stat-ed while answering "is the output stale?".
      # The walk exits early on the first newer entry, so this only bounds the
      # FRESH case (a huge `static/` tree of images). Running out of budget
      # reports "not stale": a hint is advisory, and guessing on partial
      # evidence would nag sites it cannot actually judge.
      MAX_SCANNED_ENTRIES = 20_000

      enum State
        # A real build tree: present, non-empty, no dev marker.
        Ready
        # No directory, or nothing in it.
        Missing
        # `hwaro serve` output — dev base_url baked into its pages.
        DevOutput
      end

      def oracle(dir : String, root : String = ".", sources : Array(String) = DEFAULT_SOURCES,
                 tool : String = "doctor") : Oracle
        Oracle.new(dir, root: root, sources: sources, tool: tool)
      end

      # One build-output tree, examined as an acceptance oracle.
      #
      # `dir` is the configured `[build] output_dir` (used verbatim in hints);
      # `root` is what a relative `dir` resolves against. `sources` are taken
      # AS GIVEN — the caller already knows where its content/templates/static
      # directories live, and they do not always sit under `root`.
      class Oracle
        getter dir : String
        getter state : State
        # True once the tree accepted at least one path — i.e. it was the
        # deciding evidence, not just present.
        getter? consulted : Bool

        @base : String
        @oldest_accepted : Time?
        @stale : Bool?
        @budget : Int32 = 0

        def initialize(@dir : String, root : String = ".", @sources : Array(String) = DEFAULT_SOURCES,
                       @tool : String = "doctor")
          @base = Path[@dir].absolute? ? @dir : File.join(root, @dir)
          @consulted = false
          @oldest_accepted = nil
          @stale = nil
          @state = classify
        end

        # May this tree be used as evidence at all?
        def usable? : Bool
          @state.ready?
        end

        # Does the build tree contain `relative`? Always false for a tree that
        # may not be used as evidence, so a caller never has to remember to
        # check `usable?` first.
        #
        # Path errors (an embedded NUL from a percent-decoded link target)
        # propagate exactly as the bare `File.exists?` calls this replaces did
        # — callers already degrade per link on `ArgumentError`.
        def exists?(relative : String) : Bool
          return false unless usable?
          return false if relative.empty?

          info = File.info?(File.join(@base, relative))
          return false unless info

          @consulted = true
          mtime = info.modification_time
          oldest = @oldest_accepted
          @oldest_accepted = mtime if oldest.nil? || mtime < oldest
          true
        end

        # The one-sentence advisory for this tree, or nil when it has nothing
        # to say. Callers decide WHEN it is worth showing: an unusable tree
        # only matters once something failed to resolve, so `hwaro doctor`
        # and `check-links` surface it alongside their own findings.
        def hint : String?
          case @state
          in State::Missing
            "#{label} holds no build output — run `hwaro build` first; " \
            "#{@tool} validates build output, not `hwaro serve` output (#{SERVE_OUTPUT_DIR}/)"
          in State::DevOutput
            "#{label} is `hwaro serve` output (#{DevMarker::FILENAME} marker), not a build — " \
            "#{@tool} is ignoring it; run `hwaro build` first"
          in State::Ready
            return unless @consulted && stale?
            "#{label} is older than the newest source file — #{@tool} accepted paths from stale " \
            "build output; re-run `hwaro build` to re-check them"
          end
        end

        # Display form of the configured directory, always with a trailing
        # separator so a hint reads as a directory ("public/").
        def label : String
          @dir.ends_with?(File::SEPARATOR) ? @dir : "#{@dir}#{File::SEPARATOR}"
        end

        private def classify : State
          return State::Missing unless Dir.exists?(@base)
          # The marker rule `hwaro deploy` applies: a tree stamped by serve
          # carries dev URLs and draft-inclusive routing, so it is not what a
          # deployable build would produce.
          return State::DevOutput if DevMarker.present?(@base)
          return State::Missing if empty?(@base)
          State::Ready
        rescue File::Error
          # Unreadable (permissions, an exotic mount): no evidence available.
          State::Missing
        end

        private def empty?(dir : String) : Bool
          Dir.each_child(dir) { |_| return false }
          true
        end

        # Is any source newer than the OLDEST thing the tree was believed on?
        # Memoized: `hint` is cheap to call more than once, the walk is not.
        private def stale? : Bool
          cached = @stale
          return cached unless cached.nil?

          oldest = @oldest_accepted
          return (@stale = false) unless oldest

          @budget = MAX_SCANNED_ENTRIES
          @stale = @sources.any? { |source| newer_than?(source, oldest) }
        end

        # Is `path`, or anything under it, newer than `threshold`?
        #
        # Directory mtimes count: DELETING a source file — the case that
        # leaves a route standing in the output tree with nothing behind it,
        # exactly the false negative this hint exists for — only moves its
        # parent's mtime. Hidden entries are skipped so an editor's dotfile
        # or `.DS_Store` cannot nag a site into a permanent "stale" hint.
        private def newer_than?(path : String, threshold : Time) : Bool
          return false if @budget <= 0
          @budget -= 1

          info = File.info?(path, follow_symlinks: false)
          return false unless info
          # Never follow: a link's target may sit outside the project (or loop
          # back into it), and its own mtime already stands in for the link.
          return false if info.symlink?
          return true if info.modification_time > threshold
          return false unless info.directory?

          Dir.each_child(path) do |child|
            next if child.starts_with?('.')
            return true if newer_than?(File.join(path, child), threshold)
          end
          false
        rescue ex : File::Error
          Logger.debug "Build-output staleness scan skipped #{path}: #{ex.message}"
          false
        end
      end
    end
  end
end
