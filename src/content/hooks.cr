# Content hooks module
#
# Exports all content-related lifecycle hooks.

require "./hooks/markdown_hooks"
require "./hooks/seo_hooks"

module Hwaro
  module Content
    module Hooks
      # Factory method to get all default hooks
      def self.all : Array(Core::Lifecycle::Hookable)
        [
          MarkdownHooks.new,
          SeoHooks.new,
        ] of Core::Lifecycle::Hookable
      end
    end
  end
end
