# Hugo/Zola-style Markdown render hooks.
#
# User templates under `templates/hooks/` override how individual Markdown
# elements render: `render-link.html`, `render-image.html`,
# `render-heading.html`, `render-codeblock.html`. When none of those
# templates exist, `RenderHooks.registry` is `nil` and the render path is
# EXACTLY today's — `HighlightingRenderer` (see `syntax_highlighter.cr`)
# never branches on hooks at all. `HookedRenderer` (a separate subclass)
# only comes into play once a registry exists.
#
# Values handed to hook templates arrive PRE-ESCAPED (Crinja autoescape is
# globally off for hwaro templates — see `template.cr`), so a hook template
# must emit `{{ text }}` etc. verbatim rather than piping through an escape
# filter.

require "crinja"
require "digest/md5"
require "set"
require "../../models/page"
require "../../models/config"
require "../../utils/logger"

module Hwaro
  module Content
    module Processors
      module RenderHooks
        extend self

        # The four render hooks implemented today.
        HOOK_NAMES = {"link", "image", "heading", "codeblock"}

        # Recognized but not yet implemented — `configure` stays silent
        # about these instead of warning "unknown render hook".
        FUTURE_HOOK_NAMES = {"blockquote", "table"}

        # One hook template's source plus its on-disk path (for Crinja error
        # locations); `disk_path` is nil only for templates not loaded from
        # `templates/` (never happens via `configure`, but keeps the type
        # honest for direct construction in specs).
        alias HookEntry = NamedTuple(source: String, disk_path: String?)

        # Immutable snapshot of the hook templates configured for this
        # build. Constructed once per `load_templates` call (Initialize
        # phase, and again on every `serve` template reload) and read-only
        # for the rest of the build — parallel render workers only ever
        # read `link`/`image`/`heading`/`codeblock`/`fingerprint`.
        class Registry
          getter link : HookEntry?
          getter image : HookEntry?
          getter heading : HookEntry?
          getter codeblock : HookEntry?

          # MD5 over sorted "name=source" pairs — folded into the per-page
          # template hash (render.cr#page_template_hash) so editing a hook
          # template invalidates every cached page's `--cache` entry.
          getter fingerprint : String

          def initialize(@link : HookEntry?, @image : HookEntry?, @heading : HookEntry?,
                         @codeblock : HookEntry?, @fingerprint : String)
            @warned = Set(String).new
            @warned_mutex = Mutex.new
          end

          # Emits `message` via `Logger.warn` at most once per `key` for the
          # lifetime of this registry (one build, or one `serve` reload —
          # `configure` builds a fresh `Registry` each time templates
          # reload, so a persistent misconfiguration warns again next
          # rebuild rather than going silent forever).
          def warn_once(key : String, message : String) : Nil
            should_warn = @warned_mutex.synchronize { @warned.add?(key) }
            Logger.warn(message) if should_warn
          end
        end

        @@registry : Registry? = nil

        # The active hook registry, or `nil` when no `templates/hooks/render-*`
        # template exists — the zero-cost gate every hook-aware call site
        # checks before doing any extra work.
        def self.registry : Registry?
          @@registry
        end

        # (Re)builds the hook registry from the loaded template set. Called
        # from `load_templates` (Initialize phase) right after
        # `@template_deps = TemplateDeps.new(templates)`, so it re-runs on
        # every `serve` template reload exactly like the dependency graph
        # does.
        def self.configure(templates : Hash(String, String), template_paths : Hash(String, String)) : Nil
          link : HookEntry? = nil
          image : HookEntry? = nil
          heading : HookEntry? = nil
          codeblock : HookEntry? = nil

          templates.each_key do |key|
            next unless key.starts_with?("hooks/render-")

            suffix = key.lchop("hooks/") # "render-link", "render-foo", ...
            hook_name = suffix.lchop("render-")
            entry = {source: templates[key], disk_path: template_paths[key]?}

            case hook_name
            when "link"      then link = entry
            when "image"     then image = entry
            when "heading"   then heading = entry
            when "codeblock" then codeblock = entry
            else
              unless FUTURE_HOOK_NAMES.includes?(hook_name)
                Logger.warn "unknown render hook '#{suffix}' — supported: link, image, heading, codeblock; blockquote/table are planned"
              end
            end
          end

          if link.nil? && image.nil? && heading.nil? && codeblock.nil?
            @@registry = nil
            return
          end

          pairs = [] of String
          pairs << "link=#{link[:source]}" if link
          pairs << "image=#{image[:source]}" if image
          pairs << "heading=#{heading[:source]}" if heading
          pairs << "codeblock=#{codeblock[:source]}" if codeblock
          fingerprint = Digest::MD5.hexdigest(pairs.sort!.join(''))

          @@registry = Registry.new(link, image, heading, codeblock, fingerprint)
        end

        # --- Fallback rendering context for feeds/search ---
        #
        # `render_body_cached` (markdown.cr) re-renders page bodies outside
        # the normal per-worker render path (cache-hit pages under
        # `--cache`, streaming mode). Those callers don't have a per-worker
        # Crinja env or compiled-template cache handy, so hooks get a small
        # dedicated env + cache of their own, lazily created on first use
        # and shared (mutex-guarded) across every fallback render for the
        # rest of the process.
        @@fallback_env : Crinja? = nil
        @@fallback_cache = {} of UInt64 => Crinja::Template
        @@fallback_mutex = Mutex.new

        # A `HookRenderContext` for feed/search fallback rendering, or `nil`
        # when no registry is configured. Builds a minimal page/config
        # variable set from `page` + `config` directly (no access to the
        # render phase's per-worker env/global vars).
        def self.fallback_context(page : Models::Page, config : Models::Config) : HookRenderContext?
          reg = @@registry
          return unless reg

          env = @@fallback_mutex.synchronize do
            @@fallback_env ||= begin
              engine = Content::Processors::TemplateEngine.new
              e = engine.env
              e.loader = Crinja::Loader::FileSystemLoader.new("templates/") if Dir.exists?("templates")
              e
            end
          end

          HookRenderContext.new(reg, env, @@fallback_cache, @@fallback_mutex, page_vars(page, config), config.markdown.mermaid)
        end

        # Shared page/config variable builder — exactly 6 leaf values, used
        # by both the render-phase context (render.cr#build_hook_render_context)
        # and this fallback context.
        def self.page_vars(page : Models::Page, config : Models::Config) : Hash(String, Crinja::Value)
          {
            "page" => Crinja::Value.new({
              "url"      => Crinja::Value.new(page.url),
              "title"    => Crinja::Value.new(page.title),
              "path"     => Crinja::Value.new(page.path),
              "language" => Crinja::Value.new(page.language || ""),
            } of String => Crinja::Value),
            "config" => Crinja::Value.new({
              "base_url" => Crinja::Value.new(config.base_url),
              "title"    => Crinja::Value.new(config.title),
            } of String => Crinja::Value),
          }
        end

        # Renders one hook template against a small page/config variable set
        # plus per-element vars (destination/text/alt/level/...). Mirrors
        # `ShortcodeProcessor#render_shortcode_jinja`: compiled templates are
        # cached by `source.hash ^ salt` (a hook-specific salt keeps entries
        # from colliding with the page-template/shortcode caches that can
        # share the same underlying Hash), worker-local when `@cache_mutex`
        # is `nil`, mutex-guarded otherwise. A `Crinja::TemplateError` during
        # compile or render warns once per hook per build and falls back to
        # hand-written markup matching Markd's stock output shape.
        class HookRenderContext
          # Distinct per-hook salts — arbitrary, just pairwise distinct and
          # unlikely to collide with the shortcode cache's own salt.
          SALT_LINK      = 0x4C494E4B_484F4F4B_u64
          SALT_IMAGE     = 0x494D4147_484F4F4B_u64
          SALT_HEADING   = 0x48454144_484F4F4B_u64
          SALT_CODEBLOCK = 0x434F4445_484F4F4B_u64

          def initialize(
            @registry : Registry,
            @env : Crinja,
            @template_cache : Hash(UInt64, Crinja::Template),
            @cache_mutex : Mutex?,
            @page_vars : Hash(String, Crinja::Value),
            @mermaid_bypass : Bool,
          )
          end

          def link? : Bool
            !@registry.link.nil?
          end

          def image? : Bool
            !@registry.image.nil?
          end

          def heading? : Bool
            !@registry.heading.nil?
          end

          def codeblock? : Bool
            !@registry.codeblock.nil?
          end

          # Config-decided bypass: a `mermaid` fence renders through the
          # existing mermaid pipeline (postprocess_mermaid) instead of the
          # codeblock hook when `[markdown] mermaid = true`.
          def mermaid_bypass? : Bool
            @mermaid_bypass
          end

          # `destination`/`title` arrive already escaped by the caller
          # (`HookedRenderer#link`); `text` is the captured, already-rendered
          # inner HTML of the link.
          def render_link(destination : String, title : String, text : String) : String
            hook = @registry.link
            return stock_link(destination, title, text) unless hook

            vars = @page_vars.dup
            vars["destination"] = Crinja::Value.new(destination)
            vars["title"] = Crinja::Value.new(title)
            vars["text"] = Crinja::Value.new(text)
            render_hook_template("hooks/render-link", hook, SALT_LINK, vars) { stock_link(destination, title, text) }
          end

          # `alt` is the captured plain text of the image's children (Markd's
          # `@disable_tag` protocol still applies — see `HookedRenderer#image`).
          def render_image(destination : String, alt : String, title : String) : String
            hook = @registry.image
            return stock_image(destination, alt, title) unless hook

            vars = @page_vars.dup
            vars["destination"] = Crinja::Value.new(destination)
            vars["alt"] = Crinja::Value.new(alt)
            vars["title"] = Crinja::Value.new(title)
            render_hook_template("hooks/render-image", hook, SALT_IMAGE, vars) { stock_image(destination, alt, title) }
          end

          # `id` is the already-deduped heading id (custom `{#id}` or a
          # generated slug — see `HeadingIds.assign`); `text` is the
          # captured inner HTML with any `<!--HID:...-->` marker removed.
          def render_heading(level : Int32, text : String, id : String) : String
            hook = @registry.heading
            return stock_heading(level, text, id) unless hook

            vars = @page_vars.dup
            vars["level"] = Crinja::Value.new(level)
            vars["text"] = Crinja::Value.new(text)
            vars["id"] = Crinja::Value.new(id)
            render_hook_template("hooks/render-heading", hook, SALT_HEADING, vars) { stock_heading(level, text, id) }
          end

          # `lang`/`options`/`code` arrive already escaped; `highlighted` is
          # the pre-highlighted (server mode) body HTML, or "" when
          # highlighting didn't apply — templates choose between
          # `{{ highlighted }}` and `{{ code }}`.
          def render_codeblock(lang : String, options : String, code : String, highlighted : String) : String
            hook = @registry.codeblock
            return stock_codeblock(lang, code) unless hook

            vars = @page_vars.dup
            vars["lang"] = Crinja::Value.new(lang)
            vars["options"] = Crinja::Value.new(options)
            vars["code"] = Crinja::Value.new(code)
            vars["highlighted"] = Crinja::Value.new(highlighted)
            render_hook_template("hooks/render-codeblock", hook, SALT_CODEBLOCK, vars) { stock_codeblock(lang, code) }
          end

          private def render_hook_template(template_key : String, hook : HookEntry, salt : UInt64, vars : Hash(String, Crinja::Value), & : -> String) : String
            cache_key = hook[:source].hash ^ salt
            template = fetch_or_compile(cache_key, hook, template_key)
            template.render(vars)
          rescue ex : Crinja::TemplateError
            @registry.warn_once(template_key, "Template error in render hook '#{template_key}': #{ex.message}")
            yield
          end

          private def fetch_or_compile(cache_key : UInt64, hook : HookEntry, template_key : String) : Crinja::Template
            if mutex = @cache_mutex
              mutex.synchronize { fetch_or_compile_unsynced(cache_key, hook, template_key) }
            else
              fetch_or_compile_unsynced(cache_key, hook, template_key)
            end
          end

          private def fetch_or_compile_unsynced(cache_key : UInt64, hook : HookEntry, template_key : String) : Crinja::Template
            @template_cache[cache_key]? || begin
              compiled = compile_hook_template(hook, template_key)
              @template_cache[cache_key] = compiled
              compiled
            end
          end

          # Mirrors render.cr#compile_template: attaches the on-disk path so
          # Crinja errors report `templates/hooks/render-link.html:line:col`
          # instead of an anonymous `<string>` template.
          private def compile_hook_template(hook : HookEntry, template_key : String) : Crinja::Template
            if path = hook[:disk_path]
              begin
                Crinja::Template.new(hook[:source], @env, template_key, path)
              rescue ex : Crinja::Error
                ex.template ||= Crinja::Template.new(hook[:source], @env, template_key, path, run_parser: false)
                raise ex
              end
            else
              @env.from_string(hook[:source])
            end
          end

          # --- Stock-markup fallbacks ---
          # Reconstructs Markd::HTMLRenderer's exact output shape (see
          # `lib/markd/src/markd/renderers/html_renderer.cr`) for the
          # Crinja-error path, and doubles as the "hook not configured for
          # this element" default inside each `render_*` method above.

          private def stock_link(destination : String, title : String, text : String) : String
            String.build do |io|
              io << "<a href=\"" << destination << '"'
              io << " title=\"" << title << '"' unless title.empty?
              io << '>' << text << "</a>"
            end
          end

          private def stock_image(destination : String, alt : String, title : String) : String
            String.build do |io|
              io << "<img src=\"" << destination << "\" alt=\"" << alt << '"'
              io << " title=\"" << title << '"' unless title.empty?
              io << " />"
            end
          end

          private def stock_heading(level : Int32, text : String, id : String) : String
            "<h#{level} id=\"#{id}\">#{text}</h#{level}>"
          end

          private def stock_codeblock(lang : String, code : String) : String
            if lang.empty?
              "<pre><code>#{code}</code></pre>"
            else
              "<pre><code class=\"language-#{lang}\">#{code}</code></pre>"
            end
          end
        end
      end
    end
  end
end
