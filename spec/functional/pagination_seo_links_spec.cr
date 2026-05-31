require "./support/build_helper"

# =============================================================================
# Pagination SEO links functional test.
#
# Verifies that a header rendering `{{ pagination_seo_links }}` emits
# rel=prev/next on paginated pages, and that the links carry the correct
# per-language prefix on a multilingual site (no leak to the default language,
# no doubled prefix).
# =============================================================================

PAGINATION_SEO_CONFIG = <<-TOML
  title = "Test"
  base_url = "http://localhost"
  default_language = "en"

  [pagination]
  enabled = true
  per_page = 2

  [languages.en]
  language_name = "English"

  [languages.ko]
  language_name = "한국어"
  TOML

# Section template that surfaces the SEO links (a real header would put these
# in <head>; the test only needs them in the output).
PAGINATION_SEO_TEMPLATES = {
  "page.html"    => "{{ content }}",
  "section.html" => "{{ pagination_seo_links }}{{ section_list }}",
}

private def paginated_content : Hash(String, String)
  files = {
    "posts/_index.md"    => "---\ntitle: Posts\n---\n",
    "posts/_index.ko.md" => "---\ntitle: 포스트\n---\n",
  }
  (1..5).each do |i|
    files["posts/p#{i}.md"] = "---\ntitle: EN #{i}\ndate: 2026-01-0#{i}\n---\nEN"
    files["posts/p#{i}.ko.md"] = "---\ntitle: KO #{i}\ndate: 2026-01-0#{i}\n---\nKO"
  end
  files
end

describe "Pagination SEO links" do
  it "emits rel=prev/next with the correct per-language prefix" do
    build_site(PAGINATION_SEO_CONFIG, content_files: paginated_content, template_files: PAGINATION_SEO_TEMPLATES) do
      # 5 posts / per_page 2 => pages 1,2,3 for each language.
      # EN page 2: prev -> /posts/, next -> /posts/page/3/
      en2 = File.read("public/posts/page/2/index.html")
      en2.should contain(%(<link rel="prev" href="http://localhost/posts/">))
      en2.should contain(%(<link rel="next" href="http://localhost/posts/page/3/">))

      # KO page 2: prefixed with /ko/, no leak to the en root, no /ko/ko/.
      ko2 = File.read("public/ko/posts/page/2/index.html")
      ko2.should contain(%(<link rel="prev" href="http://localhost/ko/posts/">))
      ko2.should contain(%(<link rel="next" href="http://localhost/ko/posts/page/3/">))
      ko2.should_not contain("/ko/ko/")

      # Page 1 has next only (no prev).
      en1 = File.read("public/posts/index.html")
      en1.should contain(%(<link rel="next" href="http://localhost/posts/page/2/">))
      en1.should_not contain(%(rel="prev"))
    end
  end
end
