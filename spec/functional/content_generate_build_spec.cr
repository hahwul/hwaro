require "../spec_helper"
require "./support/build_helper"

# End-to-end specs for `[[content.generate]]`: generated pages must flow
# through the FULL pipeline as first-class content — rendered HTML, section
# listings, taxonomy terms, feeds, search index — while authored files
# always win a contested path, `--cache` builds stay crash-free (a
# synthesized page has no source file to stat), and template surfaces see
# `page.extra.item` plus the `synthesized` flag.

private CONFIG = <<-TOML
  title = "Gen Site"
  base_url = "https://example.com"
  sitemap = true

  [[taxonomies]]
  name = "tags"

  [feeds]
  enabled = true

  [search]
  enabled = true

  [[content.generate]]
  source = "products.items"
  section = "products"
  slug = "sku"
  title = "name"
  body = "body_md"
  date = "released"
  description = "{{ item.name }} — {{ item.price }} USD"
  taxonomies = { tags = "categories" }
  TOML

private PRODUCTS_JSON = <<-JSON
  {"items": [
    {"sku": "Blue Widget 3000", "name": "Blue Widget", "price": 19.99, "released": "2024-01-15", "body_md": "A **blue** widget.", "categories": ["gadgets", "blue things"]},
    {"sku": "red-widget", "name": "Red Widget", "price": 24.5, "released": "2024-03-02", "body_md": "The RED one.", "categories": ["gadgets"]}
  ]}
  JSON

private PAGE_TEMPLATE = <<-HTML
  <h1>{{ page.title }}</h1>
  {% if page.synthesized %}<p class="price">{{ page.extra.item.price }}</p>{% endif %}
  <p class="synth">{{ page.synthesized }}</p>
  <main>{{ content | safe }}</main>
  HTML

private SECTION_TEMPLATE = <<-HTML
  <h1>{{ section.title }}</h1>
  <ul>{% for p in section.pages %}<li>{{ p.title }}</li>{% endfor %}</ul>
  HTML

private CONTENT_FILES = {
  "products/_index.md" => "+++\ntitle = 'Products'\n+++\n",
  "about.md"           => "+++\ntitle = 'About'\ndate = '2024-01-01'\n+++\nAuthored page.",
}

private TEMPLATE_FILES = {
  "page.html"    => PAGE_TEMPLATE,
  "section.html" => SECTION_TEMPLATE,
}

private DATA_FILES = {
  "products.json" => PRODUCTS_JSON,
}

describe "[[content.generate]] build integration" do
  it "materializes records as fully rendered first-class pages" do
    build_site(CONFIG, content_files: CONTENT_FILES, template_files: TEMPLATE_FILES, data_files: DATA_FILES) do
      blue = File.read("public/products/blue-widget-3000/index.html")
      blue.should contain("<h1>Blue Widget</h1>")
      blue.should contain(%(<p class="price">19.99</p>))
      blue.should contain(%(<p class="synth">true</p>))
      blue.should contain("A <strong>blue</strong> widget.")

      # Authored pages carry synthesized=false and no extra.item block.
      about = File.read("public/about/index.html")
      about.should contain(%(<p class="synth">false</p>))
      about.should_not contain("class=\"price\"")

      # Section listing includes generated pages.
      listing = File.read("public/products/index.html")
      listing.should contain("Blue Widget")
      listing.should contain("Red Widget")

      # Taxonomy terms registered from generated front matter.
      File.exists?("public/tags/gadgets/index.html").should be_true
      File.exists?("public/tags/blue-things/index.html").should be_true

      # Feeds, search and sitemap treat them as ordinary content.
      File.read("public/rss.xml").should contain("Blue Widget")
      File.read("public/search.json").should contain("Red Widget")
      File.read("public/sitemap.xml").should contain("/products/blue-widget-3000/")
    end
  end

  it "lets an authored file win a contested path and warns" do
    contested = CONTENT_FILES.merge({
      "products/red-widget.md" => "+++\ntitle = 'Authored Red'\n+++\nAuthored body.",
    })
    build_site(CONFIG, content_files: contested, template_files: TEMPLATE_FILES, data_files: DATA_FILES) do
      File.read("public/products/red-widget/index.html").should contain("<h1>Authored Red</h1>")
      # The generated twin was dropped, not written elsewhere: blue-widget +
      # authored red-widget only.
      Dir.glob("public/products/*/index.html").sort.should eq([
        "public/products/blue-widget-3000/index.html",
        "public/products/red-widget/index.html",
      ])
    end
  end

  it "applies [permalinks] patterns to generated pages" do
    config = CONFIG + "\n[permalinks]\nproducts = \"/shop/:slug/\"\n"
    build_site(config, content_files: CONTENT_FILES, template_files: TEMPLATE_FILES, data_files: DATA_FILES) do
      File.exists?("public/shop/blue-widget-3000/index.html").should be_true
    end
  end

  it "keeps --cache builds crash-free and re-renders synthesized pages from fresh data" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", CONFIG)
        CONTENT_FILES.each do |path, body|
          full = File.join("content", path)
          FileUtils.mkdir_p(File.dirname(full))
          File.write(full, body)
        end
        TEMPLATE_FILES.each { |path, body| FileUtils.mkdir_p("templates"); File.write(File.join("templates", path), body) }
        FileUtils.mkdir_p("data")
        File.write("data/products.json", PRODUCTS_JSON)

        run_cached = -> {
          builder = Hwaro::Core::Build::Builder.new
          Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
          builder.run(output_dir: "public", cache: true)
        }

        run_cached.call.should be_true
        # Second warm build: a synthesized page has no source file to stat —
        # must not crash, must still produce output.
        run_cached.call.should be_true
        File.exists?("public/products/blue-widget-3000/index.html").should be_true

        # A data edit must reach the output (the data digest folds into the
        # global config hash, invalidating cached pages).
        File.write("data/products.json", PRODUCTS_JSON.sub(%("name": "Blue Widget"), %("name": "Cobalt Widget")))
        run_cached.call.should be_true
        File.read("public/products/blue-widget-3000/index.html").should contain("Cobalt Widget")
      end
    end
  end
end
