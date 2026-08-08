require "../../core/lifecycle"
require "../seo/pwa"

module Hwaro
  module Content
    module Hooks
      class PwaHooks
        include Core::Lifecycle::Hookable

        def register_hooks(manager : Core::Lifecycle::Manager)
          # AfterWrite, not BeforeGenerate: sw.js checks precache URLs against
          # the files on disk and content-hashes their bytes into CACHE_NAME.
          # Running before Generate/Write meant a CLEAN build couldn't see
          # 404.html, raw files, bundle assets (Write) or the search index
          # (AfterGenerate) — those precache URLs were dropped — while a warm
          # build hashed the PREVIOUS build's bytes (clean vs warm builds
          # emitted different sw.js). AfterWrite is the last hook point before
          # Finalize (which only saves the cache), so the output tree is final.
          manager.on(Core::Lifecycle::HookPoint::AfterWrite, priority: 50, name: "pwa:generate") do |ctx|
            generate_pwa_files(ctx)
            Core::Lifecycle::HookResult::Continue
          end
        end

        private def generate_pwa_files(ctx : Core::Lifecycle::BuildContext)
          site = ctx.site
          return unless site

          Content::Seo::Pwa.generate(site, ctx.output_dir, ctx.options.verbose)
        end
      end
    end
  end
end
