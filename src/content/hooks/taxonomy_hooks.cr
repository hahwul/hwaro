# Taxonomy hooks for build lifecycle
#
# Generates taxonomy index/term pages during the Generate phase.

require "../../core/lifecycle"
require "../taxonomies"

module Hwaro
  module Content
    module Hooks
      class TaxonomyHooks
        include Core::Lifecycle::Hookable

        def register_hooks(manager : Core::Lifecycle::Manager)
          # Priority 60 so this runs BEFORE seo:generate / pwa:generate (both
          # priority 50). Hooks run highest-priority-first, so the taxonomy
          # pages must be generated and registered here before the SEO
          # generators read ctx.all_pages — otherwise the sitemap/feeds are
          # written without them and taxonomy.sitemap/feed have no effect.
          manager.on(Core::Lifecycle::HookPoint::BeforeGenerate, priority: 60, name: "taxonomy:generate") do |ctx|
            generate_taxonomies(ctx)
            Core::Lifecycle::HookResult::Continue
          end
        end

        private def generate_taxonomies(ctx : Core::Lifecycle::BuildContext)
          site = ctx.site
          return unless site

          builder = ctx.builder
          # A CLI `--cache` build keys the next one on what these templates
          # read, and keeps last build's files when nothing they render from
          # moved (Builder#taxonomy_outputs_unchanged?).
          record_reads = builder.try(&.taxonomy_render_reads_recorded?) || false
          reuse = builder.try(&.taxonomy_outputs_unchanged?(ctx)) || false
          sections = Content::Taxonomies.generate(site, ctx.output_dir, ctx.templates, ctx.options.verbose,
            builder: builder, reuse_unchanged: reuse, record_reads: record_reads)
          builder.try(&.record_taxonomy_render_reads) if record_reads
          return if sections.empty?

          # Register the generated taxonomy pages so the SEO generators include
          # them. Reassign through the setter so the all_pages cache is
          # invalidated. This intentionally augments ctx.sections only, leaving
          # site.sections (and thus the PWA precache, which reads the Site)
          # untouched.
          ctx.sections = ctx.sections + sections
        end
      end
    end
  end
end
