# Render phase — JSON-LD and Open Graph type variables.
#
# Reopens `Phases::Render`; the part require order lives in ../render.cr,
# next to the phase's tuning constants. Parts only reopen the module: no
# requires, no load-time statements (scripts/check_no_toplevel_effects.sh).
module Hwaro::Core::Build::Phases::Render
  private def build_jsonld_vars(
    vars : Hash(String, Crinja::Value),
    page : Models::Page,
    site : Models::Site,
    config : Models::Config,
    page_url_override : String?,
    og_type_override : String?,
  )
    is_homepage = home?(page)
    jsonld_article = if is_homepage || page.title.empty? || page.path == "404.html"
                       # The synthesized 404 page is neither an Article nor a
                       # collection — emit no page-level JSON-LD for it.
                       ""
                     elsif og_type_override == "website"
                       # Listing pages (section index, taxonomy index/term,
                       # author term) are collections, not articles — keep the
                       # JSON-LD @type consistent with og:type="website".
                       Content::Seo::JsonLd.collection_page(page, config, page_url_override)
                     else
                       Content::Seo::JsonLd.article(page, config, site)
                     end
    # The synthesized 404 page carries no page-level structured data (matching
    # the Article/CollectionPage suppression above) — skip its breadcrumb too.
    needs_breadcrumb = page.path != "404.html" && (!page.ancestors.empty? || !page.is_index)
    jsonld_breadcrumb = needs_breadcrumb ? Content::Seo::JsonLd.breadcrumb(page, config) : ""

    # Extended schema types (FAQ, HowTo) auto-detected from extra.schema_type
    jsonld_extra = Content::Seo::JsonLd.for_page(page, config)

    jsonld_parts = [] of String
    if is_homepage
      jsonld_home_website = Content::Seo::JsonLd.website(config)
      jsonld_parts << jsonld_home_website unless jsonld_home_website.empty?
    end
    jsonld_parts << jsonld_article unless jsonld_article.empty?
    jsonld_parts << jsonld_breadcrumb unless jsonld_breadcrumb.empty?
    jsonld_parts << jsonld_extra unless jsonld_extra.empty?
    jsonld_all = jsonld_parts.join("\n")

    vars["jsonld_article"] = Crinja::Value.new(jsonld_article)
    vars["jsonld_breadcrumb"] = Crinja::Value.new(jsonld_breadcrumb)
    # Only compute FAQ/HowTo JSON-LD when schema_type indicates it (avoids
    # per-page hash lookups + array allocations for the common case)
    schema_type_raw = page.extra["schema_type"]?.try(&.as?(String)) || ""
    schema_lower = schema_type_raw.downcase
    vars["jsonld_faq"] = Crinja::Value.new(
      schema_lower == "faqpage" || schema_lower == "faq" ? Content::Seo::JsonLd.faq_page(page, config) : ""
    )
    vars["jsonld_howto"] = Crinja::Value.new(
      schema_lower == "howto" || schema_lower == "how-to" ? Content::Seo::JsonLd.how_to(page, config) : ""
    )
    vars["jsonld"] = Crinja::Value.new(jsonld_all)
  end

  # Resolve the page kind into an `og:type` override. Returns "website"
  # for non-article pages (homepage, section indexes, taxonomy listings,
  # the synthetic 404), or `nil` to fall back to the configured
  # `[og].type` (article, by default) for content pages (gh#522).
  private def og_type_for(page : Models::Page, effective_url : String) : String?
    # 404 page is synthesized in write phase with `path = "404.html"`.
    return "website" if page.path == "404.html"
    # Explicit per-page `[extra] og_type = "website"` lets a custom listing
    # template (e.g. the blog scaffold's archives page, a plain Page with no
    # Section/taxonomy signal) declare itself a collection. Only "website" is
    # honored — it flips og:type AND the JSON-LD type to collection together;
    # any other value would desync og:type from the (Article) JSON-LD, so it
    # falls through to the default.
    if page.extra["og_type"]?.try(&.as?(String)) == "website"
      return "website"
    end
    # Taxonomy listings (`/tags/`, `/tags/<term>/`, …).
    return "website" if page.taxonomy_name
    # Section landings come from `_index.md`, which read_content parses into
    # a `Models::Section`. Key off the *type*, not `page.is_index`: a
    # page-bundle leaf (`some/post/index.md`) is a `Models::Page` with
    # `is_index = true` as well, yet it is ordinary article content. Keying
    # off `is_index` rendered og:type="website" for every page-bundle post
    # (gh#601).
    return "website" if page.is_a?(Models::Section)
    # Site / per-language homepage (`/`, `/<lang>/`). See `home?`.
    return "website" if home?(page)
    # Defensive fallback for a custom-permalink homepage remapped to root.
    return "website" if effective_url == "/" || effective_url.empty?
    nil
  end
end
