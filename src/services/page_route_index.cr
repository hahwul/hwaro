# Where a default `hwaro build` publishes each content page, for
# `tool check-links`.

require "./content_lister"
require "./generated_content"
require "../models/config"
require "../content/processors/markdown"
require "../utils/path_utils"
require "../utils/permalink_resolver"
require "../utils/logger"

module Hwaro
  module Services
    # The page URLs a default build writes, computed from the sources the
    # way the build computes them: publish state from `ContentLister` (the
    # publish-state source of truth), the URL through
    # `Utils::PermalinkResolver` (slug, `path`, `[permalinks]`, language
    # prefix, versions — the resolver the build and `tool platform` share),
    # plus every page's `aliases`.
    #
    # check-links used to treat the source tree as the URL space: `/posts/x/`
    # was live whenever `content/posts/x.md` existed. That passed links to
    # drafts and to the pre-`slug` path (the build writes neither), reported
    # every `slug`/`path`/alias/`[permalinks]` URL dead until a build had
    # populated `public/`, and resolved relative links against the source
    # directory although the browser resolves them against the page's URL.
    class PageRouteIndex
      # Publish-state label for a page that publishes but is never written
      # (`render = false`).
      NOT_RENDERED = "not rendered"

      # Expanded source path → the URL the build computes for it, whether or
      # not it publishes (relative links resolve against it).
      @urls = {} of String => String
      # Expanded source path → publish-state label (or NOT_RENDERED).
      @states = {} of String => String
      # Normalized URLs of every page and alias a default build writes.
      @published = Set(String).new
      # Published index pages (bundles and non-root sections) → their source
      # directory: the build copies a bundle's files beside the page's URL
      # (`Write#process_assets`), so `/ko/posts/b/p.png` and a slugged
      # bundle's `/posts/renamed/p.png` are real routes with no source at
      # that path.
      @bundle_dirs = {} of String => String
      # Expanded directories holding any index page: a nested bundle's files
      # belong to that bundle, not to the section around it
      # (`Page#nested_bundle?`).
      @index_dirs = Set(String).new

      def initialize(content_dir : String, config : Models::Config?)
        # Reading every page through the build's parsers replays the build's
        # diagnostics (unknown front-matter keys, unparseable dates, skipped
        # generate rules). Those belong to `hwaro build` / `tool validate`;
        # here they would bury the link report, one line per page.
        previous = Logger.level
        Logger.level = Logger::Level::Error
        begin
          lister = ContentLister.new(content_dir, GeneratedContent.infos(content_dir))
          lister.list_all.each do |info|
            if info.generated_from
              add_generated(info, config)
            else
              add_authored(info, content_dir, config)
            end
          end
        ensure
          Logger.level = previous
        end
      end

      # The URL a default build gives the page at `source`, or nil when the
      # file is not a page this index could read.
      def url_for(source : String) : String?
        @urls[File.expand_path(source)]?
      end

      # Publish-state label of the page at `source` (`published`, `draft`,
      # `future`, `expired`, or NOT_RENDERED), nil when unknown.
      def state_for(source : String) : String?
        @states[File.expand_path(source)]?
      end

      # Does a default build write a page or alias at `url`?
      def published?(url : String) : Bool
        @published.includes?(PageRouteIndex.normalize(url))
      end

      # True when `url` names a file a published bundle or section copies
      # beside its own URL.
      def bundle_asset?(url : String) : Bool
        return false if @bundle_dirs.empty?
        path = url.starts_with?('/') ? url : "/#{url}"
        return false if path.ends_with?('/')
        prefix = path
        while (slash = prefix.rindex('/', prefix.size - 2)) && slash >= 0
          prefix = prefix[0, slash + 1]
          if dir = @bundle_dirs[prefix]?
            candidate = File.join(dir, path[prefix.size..])
            return true if File.file?(candidate) && !ContentWalk.markdown?(candidate) && !nested_bundle?(dir, candidate)
          end
          break if prefix == "/"
        end
        false
      end

      # True when `file` sits in a subdirectory of `bundle_dir` that is a
      # bundle of its own.
      private def nested_bundle?(bundle_dir : String, file : String) : Bool
        root = File.expand_path(bundle_dir)
        dir = File.dirname(File.expand_path(file))
        while dir != root && dir.size > root.size
          return true if @index_dirs.includes?(dir)
          dir = File.dirname(dir)
        end
        false
      end

      # A page URL or link path in the form the build writes it: leading
      # slash, a trailing `index.html` dropped, and a trailing slash.
      def self.normalize(url : String) : String
        norm = url.starts_with?('/') ? url : "/#{url}"
        {"index.html", "index.htm"}.each do |leaf|
          if norm.ends_with?("/#{leaf}")
            norm = norm[0, norm.size - leaf.size]
            break
          end
        end
        norm.ends_with?('/') ? norm : "#{norm}/"
      end

      private def add_authored(info : ContentInfo, content_dir : String, config : Models::Config?) : Nil
        source = info.path
        relative = Path[source].relative_to(content_dir).to_s
        data = Processor::Markdown.parse(File.read(source), source)
        language = language_of(File.basename(source), config)
        url, _ = Utils::PermalinkResolver.resolve_url_lenient(
          relative, config,
          slug: data[:slug],
          custom_path: data[:custom_path],
          language: language,
          date: data[:date],
          title: data[:title],
          version: config.try(&.versions.for_path(relative)),
        )

        # `[git] use_date` gives a dateless page its first-commit date during
        # the build, and only a full `git log` knows it. When a date-token
        # permalink makes the URL depend on that date, the page stays out of
        # the index, so its links fall back to the plain existence test
        # instead of being judged against a guessed URL.
        if data[:date].nil? && (git = config.try(&.git)) && git.enabled && git.use_date
          dated, _ = Utils::PermalinkResolver.resolve_url_lenient(
            relative, config,
            slug: data[:slug],
            custom_path: data[:custom_path],
            language: language,
            date: Time.utc(2000, 1, 1),
            title: data[:title],
            version: config.try(&.versions.for_path(relative)),
          )
          return unless dated == url
        end

        key = File.expand_path(source)
        @index_dirs << File.dirname(key) if index_source?(source)
        @urls[key] = url
        @states[key] = info.published? && !data[:render] ? NOT_RENDERED : info.status
        # Registered whatever the page's state: a scheduled or draft bundle's
        # own images are judged as if it published, so its links don't fail
        # a CI gate before the page goes live.
        @bundle_dirs[url] = File.dirname(source) if index_source?(source) && File.dirname(relative) != "."
        return unless info.published? && data[:render]

        @published << PageRouteIndex.normalize(url)
        data[:aliases].each do |alias_path|
          # The build's own rule: external URLs (`mailto:`, `https://`, `//`)
          # and traversing segments (`../up`) never become redirect stubs.
          next if alias_path.empty? || Utils::PathUtils.alias_refusal(alias_path)
          @published << PageRouteIndex.normalize(alias_path)
        end
      rescue ex
        # Unreadable or malformed: the build fails on it or skips it, and
        # check-links says nothing new about it — callers fall back to the
        # plain source-file test for a page this index does not know.
        Logger.debug "check-links: no route for #{info.path}: #{ex.message}"
      end

      # `[[content.generate]]` pages have no source file, so they only ever
      # answer `published?`.
      private def add_generated(info : ContentInfo, config : Models::Config?) : Nil
        return unless info.published?
        url, _ = Utils::PermalinkResolver.resolve_url_lenient(
          info.path, config,
          slug: nil,
          custom_path: nil,
          language: language_of(File.basename(info.path), config),
          date: info.date,
          title: info.title,
          version: config.try(&.versions.for_path(info.path)),
        )
        @published << PageRouteIndex.normalize(url)
      end

      # `index.md` / `_index.md` (any language suffix): the pages whose
      # directory is a bundle.
      private def index_source?(source : String) : Bool
        stem = File.basename(source, File.extname(source))
        {"index", "_index"}.any? { |name| stem == name || stem.starts_with?("#{name}.") }
      end

      # Mirrors `ReadContent#extract_language_from_filename` plus the
      # build's default-language normalization (`about.en.md` → nil).
      private def language_of(basename : String, config : Models::Config?) : String?
        return unless config && config.multilingual?
        ext = File.extname(basename)
        stem = basename[0, basename.size - ext.size]
        idx = stem.rindex('.')
        return unless idx && idx > 0
        code = stem[(idx + 1)..]
        return if code.empty? || code == config.default_language
        code if config.languages.has_key?(code)
      end
    end
  end
end
