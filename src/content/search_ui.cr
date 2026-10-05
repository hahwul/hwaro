require "digest/md5"
require "html"
require "json"
require "../models/config"
require "./search"
require "./i18n"
require "../utils/file_safe"

module Hwaro
  module Content
    # The built-in search client (`[search] ui = true`): a dependency-free
    # script + stylesheet published under `assets/hwaro-search/`, and the
    # `{{ search_tags }}` markup that loads them. The script reads its
    # settings from a `data-` attribute, so pages need no inline script.
    module SearchUi
      extend self

      ASSET_DIR = "assets/hwaro-search"
      JS        = {{ read_file("#{__DIR__}/search_ui/search.js") }}
      CSS       = {{ read_file("#{__DIR__}/search_ui/search.css") }}

      # i18n keys (`i18n/<lang>.toml`) and their English defaults. The count
      # line takes `{count}`; a `[search.results_count]` table with `one`
      # and `other` picks the form the way the `pluralize` filter does.
      DEFAULT_STRINGS = {
        "placeholder"   => "Search",
        "no_results"    => "No results",
        "results_one"   => "{count} result",
        "results_other" => "{count} results",
        "close"         => "Close",
      }

      def asset_paths(output_dir : String) : Array(String)
        [File.join(output_dir, ASSET_DIR, "search.js"), File.join(output_dir, ASSET_DIR, "search.css")]
      end

      # Every file the UI publishes (claimed by the builder): none unless on.
      def published_outputs(config : Models::Config, output_dir : String) : Array(String)
        config.search.ui_enabled? ? asset_paths(output_dir) : [] of String
      end

      # Writes the two assets, leaving a byte-identical file untouched so its
      # mtime (and the SRI memo keyed on it) survives warm builds. They win
      # over a same-path file under `static_dir`, which is worth a warning.
      def write_assets(config : Models::Config, output_dir : String, verbose : Bool = false, static_dir : String = "static") : Array(String)
        paths = published_outputs(config, output_dir)
        paths.zip([JS, CSS]) do |path, body|
          user_file = File.join(static_dir, ASSET_DIR, File.basename(path))
          if File.exists?(user_file)
            Logger.warn "#{user_file} is replaced by the built-in search UI's own file ([search] ui = true); theme it with the --hwaro-search-* CSS properties instead."
          end
          next if File.file?(path) && File.read(path) == body
          Utils::FileSafe.mkdir_p(File.dirname(path))
          Utils::FileSafe.atomic_write(path, body)
          Logger.action :create, path if verbose
        end
        paths
      end

      # `search_tags` per language code (every configured language, the
      # default first). Empty when the UI is off. `cache_bust` false drops
      # the `?v=`; `sri_root` (the output dir, nil when SRI is off) adds
      # `integrity` from the emitted files.
      def tags_by_language(config : Models::Config, translations : I18n::TranslationData, cache_bust : Bool, sri_root : String?) : Hash(String, String)
        result = {} of String => String
        return result unless config.search.ui_enabled?
        ([config.default_language] + config.languages.keys).uniq.each do |lang|
          result[lang] = tags(config, lang, translations, cache_bust, sri_root)
        end
        result
      end

      def tags(config : Models::Config, lang : String, translations : I18n::TranslationData, cache_bust : Bool, sri_root : String?) : String
        css_path = "/#{ASSET_DIR}/search.css"
        js_path = "/#{ASSET_DIR}/search.js"
        css_href = config.with_base_path(css_path) + (cache_bust ? Models.cache_bust_suffix(CSS_DIGEST) : "")
        js_src = config.with_base_path(js_path) + (cache_bust ? Models.cache_bust_suffix(JS_DIGEST) : "")
        payload = config_payload(config, lang, translations)
        String.build do |io|
          io << %(<link rel="stylesheet" href="#{HTML.escape(css_href)}") << Models.integrity_attr(sri_root, css_path) << ">\n"
          io << %(<script defer src="#{HTML.escape(js_src)}") << Models.integrity_attr(sri_root, js_path)
          io << %( data-hwaro-search-config="#{HTML.escape(payload)}"></script>)
        end
      end

      # The client's settings, as JSON (HTML-escaped into the attribute by
      # `tags`). `lang` is set on multilingual sites only: the client then
      # keeps that language's shards and records.
      def config_payload(config : Models::Config, lang : String, translations : I18n::TranslationData) : String
        search = config.search
        sharded = search.sharded?
        JSON.build do |json|
          json.object do
            if !sharded || search.single_file
              json.field "index", config.with_base_path("/#{File.basename(search.filename)}")
            end
            json.field "manifest", config.with_base_path("/#{Search::SHARDS_DIR}/#{Search::MANIFEST_FILENAME}") if sharded
            json.field "base", config.base_path
            json.field "lang", lang if config.multilingual?
            json.field "cjk", search.tokenize_cjk
            json.field "facets", search.facets
            json.field "i18n" do
              json.object do
                strings(lang, config.default_language, translations).each { |k, v| json.field k, v }
              end
            end
          end
        end
      end

      # The page language's own strings first, then the default language's,
      # then English. A count form (`results_count.one`) beats the plain
      # `results_count` only within the same language.
      def strings(lang : String, default_lang : String, translations : I18n::TranslationData) : Hash(String, String)
        codes = [lang, default_lang].uniq
        {
          "placeholder"   => lookup(translations, codes, "placeholder"),
          "no_results"    => lookup(translations, codes, "no_results"),
          "results_one"   => lookup(translations, codes, "results_count.one", "results_count"),
          "results_other" => lookup(translations, codes, "results_count.other", "results_count"),
          "close"         => lookup(translations, codes, "close"),
        }.to_h { |name, value| {name, value || DEFAULT_STRINGS[name]} }
      end

      private def lookup(translations : I18n::TranslationData, codes : Array(String), *keys : String) : String?
        codes.each do |code|
          next unless entries = translations[code]?
          keys.each { |key| entries["search.#{key}"]?.try { |value| return value } }
        end
        nil
      end

      private JS_DIGEST  = Digest::MD5.hexdigest(JS)[0, 8]
      private CSS_DIGEST = Digest::MD5.hexdigest(CSS)[0, 8]
    end
  end
end
