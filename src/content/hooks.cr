# Content hooks module
#
# Exports all content-related lifecycle hooks.

require "./hooks/seo_hooks"
require "./hooks/taxonomy_hooks"
require "./hooks/sass_hooks"
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
      # Markdown parsing/rendering is NOT hook-based: the builder's
      # ParseContent and Render phases own it. A historical MarkdownHooks
      # hookable duplicated that entire pipeline sequentially (its output
      # was overwritten by the phases) and was removed — front-matter
      # parsing, draft filtering, URL calculation, summary rendering, and
      # markdown transforms all live in the phase implementations now.
      def self.all : Array(Core::Lifecycle::Hookable)
        [
          SeoHooks.new,
          TaxonomyHooks.new,
          SassHooks.new,
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
