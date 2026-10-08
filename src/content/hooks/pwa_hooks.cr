require "../../core/lifecycle"
require "../seo/pwa"

module Hwaro
  module Content
    module Hooks
      class PwaHooks
        include Core::Lifecycle::Hookable

        def register_hooks(manager : Core::Lifecycle::Manager)
          # AfterFinalize, not BeforeGenerate/AfterWrite: sw.js checks precache
          # URLs against the files on disk and content-hashes their bytes into
          # CACHE_NAME. Running before Generate/Write meant a CLEAN build
          # couldn't see 404.html, raw files, bundle assets (Write) or the
          # search index (AfterGenerate), while a warm build hashed the
          # PREVIOUS build's bytes. AfterWrite fixed that but still ran before
          # Finalize prunes the output of deleted/unpublished pages (`--cache`
          # and serve rebuilds keep the directory), so sw.js precached pages
          # that were about to disappear and cache.addAll() 404'd. After
          # Finalize the output tree is final.
          manager.on(Core::Lifecycle::HookPoint::AfterFinalize, priority: 50, name: "pwa:generate") do |ctx|
            generate_pwa_files(ctx)
            Core::Lifecycle::HookResult::Continue
          end
        end

        private def generate_pwa_files(ctx : Core::Lifecycle::BuildContext)
          site = ctx.site
          return unless site

          localize = ctx.builder.try { |builder| ->(url : String) { builder.privacy_url(url) } }
          Content::Seo::Pwa.generate(site, ctx.output_dir, ctx.options.verbose, localize)
        end
      end
    end
  end
end
