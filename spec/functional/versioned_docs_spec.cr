require "./support/build_helper"

# =============================================================================
# Versioned documentation (`[versions]` + `[[versions.list]]`) functional tests
#
# Builds a small two-version fixture and asserts the output tree, the URL
# mapping for both `latest_at_root` modes, the multilingual combination, the
# `page.version` / `page.version_links` / `versions` template surface,
# counterpart lookup, in-version scoping (prev/next, ancestors, sections,
# taxonomies), canonical/noindex, and the search/sitemap/feeds switches.
# =============================================================================

VERSIONS_CONFIG = <<-TOML
  title = "Versioned"
  base_url = "http://localhost"

  [versions]
  latest_at_root = true

  [[versions.list]]
  name = "v2"
  label = "2.x (latest)"
  path = "docs/v2"
  latest = true

  [[versions.list]]
  name = "v1"
  label = "1.x"
  path = "docs/v1"
  TOML

VERSIONS_CONFIG_PREFIXED = VERSIONS_CONFIG.sub("latest_at_root = true", "latest_at_root = false")

# Two versions; `install` exists in both, `plugins` only in v2, `legacy`
# only in v1. Weights fix the reading order.
private def versioned_content : Hash(String, String)
  {
    "docs/v2/_index.md"  => "+++\ntitle = \"Docs 2.x\"\nsort_by = \"weight\"\n+++\n",
    "docs/v2/install.md" => "+++\ntitle = \"Install 2\"\nweight = 1\ntags = [\"setup\"]\n+++\nInstall v2",
    "docs/v2/plugins.md" => "+++\ntitle = \"Plugins\"\nweight = 2\n+++\nPlugins v2",
    "docs/v1/_index.md"  => "+++\ntitle = \"Docs 1.x\"\nsort_by = \"weight\"\n+++\n",
    "docs/v1/install.md" => "+++\ntitle = \"Install 1\"\nweight = 1\ntags = [\"setup\"]\n+++\nInstall v1",
    "docs/v1/legacy.md"  => "+++\ntitle = \"Legacy\"\nweight = 2\n+++\nLegacy v1",
  }
end

SWITCHER_TEMPLATE = <<-HTML
  URL={{ page_url }}
  V={{ page.version.name }}|{{ page.version.label }}|{{ page.version.latest }}|{{ page.version.url }}
  LINKS={% for l in page.version_links %}{{ l.name }}:{{ l.url }}:{{ l.exists }}:{{ l.current }},{% endfor %}
  ALL={% for v in versions %}{{ v.name }}={{ v.url }},{% endfor %}
  LATEST={{ versions.latest.name }}@{{ versions.latest.url }}
  LOWER={% if page.lower %}{{ page.lower.url }}{% else %}-{% endif %}
  HIGHER={% if page.higher %}{{ page.higher.url }}{% else %}-{% endif %}
  CRUMBS={% for a in page.ancestors %}{{ a.url }},{% endfor %}
  SEO={{ canonical_tag }}
  {{ content }}
  HTML

private def read(path : String) : String
  File.exists?(path).should be_true
  File.read(path)
end

describe "Versioned docs: URL mapping (latest_at_root = true)" do
  it "renders the latest version at the parent's natural URL and older versions under /<name>/" do
    build_site(VERSIONS_CONFIG, content_files: versioned_content, template_files: {
      "page.html"    => SWITCHER_TEMPLATE,
      "section.html" => SWITCHER_TEMPLATE,
    }) do
      # Latest (v2) collapses onto /docs/
      File.exists?("public/docs/index.html").should be_true
      File.exists?("public/docs/install/index.html").should be_true
      File.exists?("public/docs/plugins/index.html").should be_true
      File.exists?("public/docs/v2/index.html").should be_false
      File.exists?("public/docs/v2/install/index.html").should be_false

      # Older (v1) keeps its name segment
      File.exists?("public/docs/v1/index.html").should be_true
      File.exists?("public/docs/v1/install/index.html").should be_true
      File.exists?("public/docs/v1/legacy/index.html").should be_true

      read("public/docs/install/index.html").should contain("URL=/docs/install/")
      read("public/docs/v1/install/index.html").should contain("URL=/docs/v1/install/")
    end
  end

  it "exposes page.version, page.version_links (counterparts + exists) and the versions global" do
    build_site(VERSIONS_CONFIG, content_files: versioned_content, template_files: {
      "page.html"    => SWITCHER_TEMPLATE,
      "section.html" => SWITCHER_TEMPLATE,
    }) do
      v2 = read("public/docs/install/index.html")
      v2.should contain("V=v2|2.x (latest)|true|/docs/")
      v2.should contain("LINKS=v2:/docs/install/:true:true,v1:/docs/v1/install/:true:false,")
      v2.should contain("ALL=v2=/docs/,v1=/docs/v1/,")
      v2.should contain("LATEST=v2@/docs/")

      # plugins.md has no v1 counterpart → v1 root, exists = false
      plugins = read("public/docs/plugins/index.html")
      plugins.should contain("LINKS=v2:/docs/plugins/:true:true,v1:/docs/v1/:false:false,")

      # legacy.md has no v2 counterpart → v2 root (which is /docs/), exists = false
      legacy = read("public/docs/v1/legacy/index.html")
      legacy.should contain("V=v1|1.x|false|/docs/v1/")
      legacy.should contain("LINKS=v2:/docs/:false:false,v1:/docs/v1/legacy/:true:true,")

      # Version root sections link to each other's roots
      read("public/docs/v1/index.html").should contain("LINKS=v2:/docs/:true:false,v1:/docs/v1/:true:true,")
    end
  end

  it "keeps prev/next and breadcrumbs inside one version" do
    build_site(VERSIONS_CONFIG, content_files: versioned_content, template_files: {
      "page.html"    => SWITCHER_TEMPLATE,
      "section.html" => SWITCHER_TEMPLATE,
    }) do
      # v2 chain: /docs/ → install → plugins (end)
      read("public/docs/plugins/index.html").should contain("HIGHER=-")
      read("public/docs/install/index.html").should contain("LOWER=/docs/\n")
      read("public/docs/install/index.html").should contain("HIGHER=/docs/plugins/")
      # v1 chain: /docs/v1/ → install → legacy (end); never crosses into v2
      read("public/docs/v1/index.html").should contain("LOWER=-")
      read("public/docs/v1/install/index.html").should contain("LOWER=/docs/v1/\n")
      read("public/docs/v1/legacy/index.html").should contain("HIGHER=-")
      # breadcrumbs stop at the version root
      read("public/docs/v1/install/index.html").should contain("CRUMBS=/docs/v1/,")
      read("public/docs/install/index.html").should contain("CRUMBS=/docs/,")
    end
  end

  it "canonicalizes older versions to the latest counterpart and adds noindex" do
    build_site(VERSIONS_CONFIG, content_files: versioned_content, template_files: {
      "page.html"    => SWITCHER_TEMPLATE,
      "section.html" => SWITCHER_TEMPLATE,
    }) do
      old = read("public/docs/v1/install/index.html")
      old.should contain(%(<link rel="canonical" href="http://localhost/docs/install/">))
      old.should contain(%(<meta name="robots" content="noindex">))

      # No counterpart → self canonical, still noindex
      legacy = read("public/docs/v1/legacy/index.html")
      legacy.should contain(%(<link rel="canonical" href="http://localhost/docs/v1/legacy/">))
      legacy.should contain(%(<meta name="robots" content="noindex">))

      latest = read("public/docs/install/index.html")
      latest.should contain(%(<link rel="canonical" href="http://localhost/docs/install/">))
      latest.should_not contain("noindex")
    end
  end

  it "respects noindex_old = false" do
    build_site(VERSIONS_CONFIG.sub("latest_at_root = true", "latest_at_root = true\nnoindex_old = false"),
      content_files: versioned_content, template_files: {
      "page.html"    => SWITCHER_TEMPLATE,
      "section.html" => SWITCHER_TEMPLATE,
    }) do
      old = read("public/docs/v1/install/index.html")
      old.should contain(%(<link rel="canonical" href="http://localhost/docs/install/">))
      old.should_not contain("noindex")
    end
  end
end

describe "Versioned docs: URL mapping (latest_at_root = false)" do
  it "keeps every version under its name and redirects the parent URL to the latest" do
    build_site(VERSIONS_CONFIG_PREFIXED, content_files: versioned_content, template_files: {
      "page.html"    => SWITCHER_TEMPLATE,
      "section.html" => SWITCHER_TEMPLATE,
    }) do
      File.exists?("public/docs/v2/index.html").should be_true
      File.exists?("public/docs/v2/install/index.html").should be_true
      File.exists?("public/docs/v1/install/index.html").should be_true
      File.exists?("public/docs/install/index.html").should be_false

      stub = read("public/docs/index.html")
      stub.should contain("/docs/v2/")
      stub.downcase.should contain("refresh")

      v2 = read("public/docs/v2/install/index.html")
      v2.should contain("V=v2|2.x (latest)|true|/docs/v2/")
      v2.should contain("LINKS=v2:/docs/v2/install/:true:true,v1:/docs/v1/install/:true:false,")
      v2.should contain("LATEST=v2@/docs/v2/")
    end
  end

  it "does not overwrite an authored parent index with the redirect stub" do
    content = versioned_content.merge({"docs/_index.md" => "+++\ntitle = \"Docs Hub\"\n+++\nHub"})
    build_site(VERSIONS_CONFIG_PREFIXED, content_files: content, template_files: {
      "page.html"    => SWITCHER_TEMPLATE,
      "section.html" => "HUB {{ section.title }} SUBS={% for s in section.subsections %}{{ s.name }},{% endfor %} PAGES={% for p in section.pages %}{{ p.url }},{% endfor %}",
    }) do
      hub = read("public/docs/index.html")
      hub.should contain("HUB Docs Hub")
      hub.should_not contain("refresh")
      # Version roots are not subsections/pages of the unversioned parent
      hub.should contain("SUBS= ")
      hub.should contain("PAGES=")
      hub.should_not contain("/docs/v1/")
    end
  end
end

describe "Versioned docs: multilingual" do
  it "puts the language prefix first and the version after" do
    config = VERSIONS_CONFIG + "\n  default_language = \"en\"\n  [languages.ko]\n  language_name = \"한국어\"\n"
    content = versioned_content.merge({
      "docs/v2/install.ko.md" => "+++\ntitle = \"설치 2\"\n+++\n설치 v2",
      "docs/v1/install.ko.md" => "+++\ntitle = \"설치 1\"\n+++\n설치 v1",
      "docs/v1/_index.ko.md"  => "+++\ntitle = \"문서 1.x\"\n+++\n",
    })
    build_site(config, content_files: content, template_files: {
      "page.html"    => SWITCHER_TEMPLATE,
      "section.html" => SWITCHER_TEMPLATE,
    }) do
      File.exists?("public/ko/docs/install/index.html").should be_true
      File.exists?("public/ko/docs/v1/install/index.html").should be_true
      ko = read("public/ko/docs/v1/install/index.html")
      ko.should contain("URL=/ko/docs/v1/install/")
      ko.should contain("V=v1|1.x|false|/ko/docs/v1/")
      ko.should contain("LINKS=v2:/ko/docs/install/:true:false,v1:/ko/docs/v1/install/:true:true,")
      ko.should contain("ALL=v2=/ko/docs/,v1=/ko/docs/v1/,")
      # Korean old page canonicalizes to the Korean latest counterpart
      ko.should contain(%(<link rel="canonical" href="http://localhost/ko/docs/install/">))
      # English counterpart links are unaffected
      read("public/docs/v1/install/index.html").should contain("LINKS=v2:/docs/install/:true:false,")
    end
  end
end

describe "Versioned docs: discovery switches" do
  it "keeps older versions out of search.json and sitemap.xml by default" do
    build_site(VERSIONS_CONFIG + "\n  [search]\n  enabled = true\n  [sitemap]\n  enabled = true\n", content_files: versioned_content, template_files: {
      "page.html" => "{{ content }}", "section.html" => "{{ content }}",
    }) do
      search = read("public/search.json")
      search.should contain("/docs/install/")
      search.should_not contain("/docs/v1/")
      search.should contain(%("version":"v2"))
      search.should_not contain(%("version":"v1"))
      sitemap = read("public/sitemap.xml")
      sitemap.should contain("<loc>http://localhost/docs/install/</loc>")
      sitemap.should_not contain("/docs/v1/")
    end
  end

  it "indexes every version with search = \"all\" and tags records with their version" do
    build_site(VERSIONS_CONFIG.sub("latest_at_root = true", "latest_at_root = true\nsearch = \"all\"") + "\n  [search]\n  enabled = true\n  [sitemap]\n  enabled = true\n",
      content_files: versioned_content, template_files: {
      "page.html" => "{{ content }}", "section.html" => "{{ content }}",
    }) do
      search = read("public/search.json")
      search.should contain("/docs/v1/install/")
      search.should contain(%("version":"v1"))
      search.should contain(%("version":"v2"))
      read("public/sitemap.xml").should contain("<loc>http://localhost/docs/v1/install/</loc>")
    end
  end

  it "feeds only the latest version unless feeds = \"all\"" do
    feed_cfg = "\n  [feeds]\n  enabled = true\n  type = \"rss\"\n"
    build_site(VERSIONS_CONFIG + feed_cfg, content_files: versioned_content, template_files: {
      "page.html" => "{{ content }}", "section.html" => "{{ content }}",
    }) do
      rss = read("public/rss.xml")
      rss.should contain("/docs/install/")
      rss.should_not contain("/docs/v1/")
    end
    build_site(VERSIONS_CONFIG.sub("latest_at_root = true", "latest_at_root = true\nfeeds = \"all\"") + feed_cfg,
      content_files: versioned_content, template_files: {
      "page.html" => "{{ content }}", "section.html" => "{{ content }}",
    }) do
      read("public/rss.xml").should contain("/docs/v1/install/")
    end
  end

  it "collects taxonomy terms from the latest version only unless taxonomies = \"all\"" do
    tax_cfg = "\n  [[taxonomies]]\n  name = \"tags\"\n"
    tpl = {
      "page.html"          => "{{ content }}",
      "section.html"       => "{{ content }}",
      "taxonomy_term.html" => "TERM={{ content }}",
    }
    build_site(VERSIONS_CONFIG + tax_cfg, content_files: versioned_content, template_files: tpl) do
      term = read("public/tags/setup/index.html")
      term.should contain("/docs/install/")
      term.should_not contain("/docs/v1/")
    end
    build_site(VERSIONS_CONFIG.sub("latest_at_root = true", "latest_at_root = true\ntaxonomies = \"all\"") + tax_cfg,
      content_files: versioned_content, template_files: tpl) do
      term = read("public/tags/setup/index.html")
      term.should contain("/docs/install/")
      term.should contain("/docs/v1/install/")
    end
  end

  it "keeps llms.txt latest-only" do
    build_site(VERSIONS_CONFIG + "\n  [llms]\n  enabled = true\n", content_files: versioned_content, template_files: {
      "page.html" => "{{ content }}", "section.html" => "{{ content }}",
    }) do
      llms = read("public/llms.txt")
      llms.should contain("/docs/install/")
      llms.should_not contain("/docs/v1/")
    end
  end
end

describe "Versioned docs: base_path and section scoping" do
  it "writes the parent redirect stub with base_path and keeps template URLs site-relative" do
    cfg = VERSIONS_CONFIG_PREFIXED.sub(%(base_url = "http://localhost"), %(base_url = "http://localhost/sub"))
    build_site(cfg, content_files: versioned_content, template_files: {
      "page.html"    => SWITCHER_TEMPLATE,
      "section.html" => SWITCHER_TEMPLATE,
    }) do
      read("public/docs/index.html").should contain("/sub/docs/v2/")
      v1 = read("public/docs/v1/install/index.html")
      v1.should contain("LINKS=v2:/docs/v2/install/:true:false,")
      v1.should contain(%(<link rel="canonical" href="http://localhost/sub/docs/v2/install/">))
    end
  end

  it "scopes get_section() listings to one version" do
    build_site(VERSIONS_CONFIG, content_files: versioned_content, template_files: {
      "page.html"    => "S={% for p in get_section(page.section).pages %}{{ p.url }},{% endfor %}",
      "section.html" => "{{ content }}",
    }) do
      read("public/docs/v1/install/index.html").should contain("S=/docs/v1/install/,/docs/v1/legacy/,")
      read("public/docs/install/index.html").should contain("S=/docs/install/,/docs/plugins/,")
    end
  end

  it "scopes front-matter menu registrations to the page's version" do
    content = versioned_content.merge({
      "docs/v2/install.md" => "+++\ntitle = \"Install 2\"\nweight = 1\nmenus = [\"main\"]\n+++\nInstall v2",
      "docs/v1/install.md" => "+++\ntitle = \"Install 1\"\nweight = 1\nmenus = [\"main\"]\n+++\nInstall v1",
      "about.md"           => "+++\ntitle = \"About\"\nmenus = [\"main\"]\n+++\nAbout",
    })
    menu_tpl = "MENU={% for m in get_menu(name=\"main\") %}{{ m.url }},{% endfor %}"
    build_site(VERSIONS_CONFIG, content_files: content, template_files: {
      "page.html" => menu_tpl, "section.html" => menu_tpl,
    }) do
      read("public/docs/v1/install/index.html").should contain("MENU=/about/,/docs/v1/install/,")
      read("public/docs/install/index.html").should contain("MENU=/about/,/docs/install/,")
      # Unversioned pages see the latest version's registrations only
      read("public/about/index.html").should contain("MENU=/about/,/docs/install/,")
    end
  end
end

describe "Versioned docs: disabled" do
  it "does not expose version variables when no versions are configured" do
    build_site(BASIC_CONFIG, content_files: {"docs/v1/a.md" => "+++\ntitle = \"A\"\n+++\nA"}, template_files: {
      "page.html" => "V=[{{ page.version }}]|L=[{% for l in page.version_links %}x{% endfor %}]|{{ versions is defined }}",
    }) do
      html = read("public/docs/v1/a/index.html")
      html.should contain("V=[]|L=[]|false")
    end
  end
end
