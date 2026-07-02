# Content hooks module
#
# Exports all content-related lifecycle hooks.

require "./hooks/markdown_hooks"
require "./hooks/seo_hooks"
require "./hooks/taxonomy_hooks"
require "./hooks/asset_hooks"
require "./hooks/pwa_hooks"
require "./hooks/amp_hooks"
require "./hooks/og_image_hooks"
require "./hooks/image_hooks"

module Hwaro
  module Content
    module Hooks
      # Factory method to get all default hooks.
      #
      # MarkdownHooks is intentionally NOT registered: the builder's
      # ParseContent phase default only steps aside for a BeforeParseContent
      # hook (parse_content.cr), and MarkdownHooks registered at
      # AfterReadContent/BeforeRender — so every one of its file reads,
      # front-matter parses, summary renders, and sequential whole-site
      # markdown renders was immediately redone (in parallel, with cascades
      # and template-name normalization) by the ParseContent/Render phases.
      # Removing it halves the markdown work per build; the only output it
      # contributed — `page.content` for cache-hit pages that Generate's
      # feeds/search read — is covered by their render_body_cached fallback.
      def self.all : Array(Core::Lifecycle::Hookable)
        [
          SeoHooks.new,
          TaxonomyHooks.new,
          AssetHooks.new,
          PwaHooks.new,
          AmpHooks.new,
          OgImageHooks.new,
          ImageHooks.new,
        ] of Core::Lifecycle::Hookable
      end
    end
  end
end
