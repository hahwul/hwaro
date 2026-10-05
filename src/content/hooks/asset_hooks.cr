# Asset pipeline hooks for build lifecycle
#
# Processes CSS/JS bundles during the build, producing minified and
# fingerprinted output files. The resulting manifest is exposed to
# templates via the `asset()` function.

require "../../core/lifecycle"
require "../../assets/pipeline"

module Hwaro
  module Content
    module Hooks
      class AssetHooks
        include Core::Lifecycle::Hookable

        # Class-level manifest shared with template functions
        @@manifest = {} of String => String
        @@manifest_mutex = Mutex.new
        # Output directory of the current build, for `asset_integrity()`.
        @@output_dir : String? = nil
        # Absolute output path => source file, for the outputs the Write phase
        # copies verbatim AFTER rendering (page-bundle assets, `[content.files]`).
        @@sources = {} of String => String
        # Absolute output paths this build publishes and has written by
        # Render (static copies, Sass outputs, bundles). Nil when unknown (no
        # build set it): any file on disk then counts.
        @@published : Set(String)? = nil

        def register_hooks(manager : Core::Lifecycle::Manager)
          manager.on(Core::Lifecycle::HookPoint::AfterInitialize, priority: 40, name: "assets:process") do |ctx|
            process_assets(ctx)
            Core::Lifecycle::HookResult::Continue
          end
        end

        def self.manifest : Hash(String, String)
          @@manifest_mutex.synchronize { @@manifest }
        end

        # Replace the class-level manifest (serve-mode SCSS/asset recompile).
        # Full builds go through process_assets; this keeps fingerprint paths
        # in sync when only static files changed.
        def self.replace_manifest(manifest : Hash(String, String))
          @@manifest_mutex.synchronize { @@manifest = manifest }
        end

        def self.output_dir : String?
          @@manifest_mutex.synchronize { @@output_dir }
        end

        def self.output_dir=(dir : String?)
          @@manifest_mutex.synchronize { @@output_dir = dir }
        end

        # The emitted file `asset(name)` points to: the manifest bundle, else
        # `name` under the output root. Nil before a build ran, or when the
        # path leaves the output directory.
        def self.output_path(name : String) : String?
          return unless dir = output_dir
          url = manifest[name]? || (name.starts_with?('/') ? name : "/#{name}")
          path = File.join(dir, url.lchop('/'))
          Utils::OutputGuard.within_output_dir?(path, dir) ? path : nil
        end

        def self.publish(sources : Hash(String, String), published : Set(String)?)
          @@manifest_mutex.synchronize do
            @@sources = sources
            @@published = published
          end
        end

        # `asset_integrity(name)`: the SRI value of what `asset(name)` serves.
        # A file the Write phase has yet to copy (or, under `--cache`, still
        # holds the previous copy of) is hashed from its source — the copy is
        # verbatim — so cold and warm builds agree. Any other path counts only
        # when this build publishes it: a `--cache` build keeps the previous
        # build's files until Finalize prunes them, and hashing one of those
        # (a deleted static file, a now-withheld bundle asset) printed the
        # value of a file about to vanish where a cold build raised. Nil when
        # nothing is published there.
        def self.integrity(name : String, record : Bool = true) : String?
          return unless path = output_path(name)
          absolute = File.expand_path(path)
          source, published = @@manifest_mutex.synchronize { {@@sources[absolute]?, @@published} }
          return Utils::SriCache.sri(source, record) if source
          return if published && !published.includes?(absolute)
          Utils::SriCache.sri(path, record)
        end

        private def process_assets(ctx : Core::Lifecycle::BuildContext)
          AssetHooks.output_dir = ctx.output_dir
          config = ctx.config
          return unless config && config.assets.enabled

          pipeline = Assets::Pipeline.new(config.assets, config.sass.enabled)
          pipeline.process(ctx.output_dir)

          AssetHooks.replace_manifest(pipeline.manifest)

          # Fingerprinted bundle names change with their contents, and a
          # `--cache` build keeps the output directory — so every CSS/JS edit
          # used to leave the previous `main.<hash>.css` behind, published and
          # deployed forever. Claiming what this build wrote lets the Finalize
          # phase delete the ones it no longer writes.
          if builder = ctx.builder
            pipeline.written_paths.each { |path| builder.claim_generated_output(path) }
          end

          if pipeline.manifest.size > 0
            Logger.info "  Assets: #{pipeline.manifest.size} bundle(s) processed."
          end
        end
      end
    end
  end
end
