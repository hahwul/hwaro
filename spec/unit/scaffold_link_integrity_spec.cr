require "../spec_helper"
require "../../src/models/config"
require "../../src/services/scaffolds/blog"
require "../../src/services/scaffolds/docs"
require "../../src/services/scaffolds/book"
require "../../src/services/scaffolds/simple"
require "../../src/services/scaffolds/bare"

# Prevents regressions like `.html`-suffixed links to pages hwaro serves at `/path/`.

private def content_path_to_url(path : String) : String
  return "/" if path == "index.md"
  stripped = path.sub(/\.md\z/, "")
  if stripped.ends_with?("/_index")
    "/#{stripped.sub(/\/_index\z/, "")}/"
  else
    "/#{stripped}/"
  end
end

# Routes hwaro generates automatically when taxonomies are enabled.
AUTO_ROUTES = ["/tags/", "/categories/", "/authors/"]

# File-extension whitelist for static assets — these are not page URLs.
ASSET_EXT_RE = /\.(jpg|jpeg|png|gif|svg|webp|ico|pdf|mp4|webm|ogg|mp3|wav|json|xml|txt|zip|css|js)\z/i

private def extract_internal_links(body : String) : Array(String)
  # Strip fenced + inline code so example syntax inside code blocks doesn't count.
  sanitized = body.gsub(/```[\s\S]*?```/, "").gsub(/`[^`\n]*`/, "")
  links = [] of String
  sanitized.scan(/!?\[[^\]]*\]\((\/[^)\s]*)\)/).each do |m|
    links << m[1]
  end
  # Raw-HTML links too — scaffold bodies compose designed blocks like the
  # docs landing's `<a class="link-card" href="/getting-started/">`.
  sanitized.scan(/href="(\/[^"]*)"/).each do |m|
    links << m[1]
  end
  links
end

private def scaffold_fixtures
  {
    "blog"   => Hwaro::Services::Scaffolds::Blog.new,
    "docs"   => Hwaro::Services::Scaffolds::Docs.new,
    "book"   => Hwaro::Services::Scaffolds::Book.new,
    "simple" => Hwaro::Services::Scaffolds::Simple.new,
    "bare"   => Hwaro::Services::Scaffolds::Bare.new,
  }
end

private def load_config_from_string(toml : String) : Hwaro::Models::Config
  File.tempfile("hwaro-scaffold-config", ".toml") do |file|
    file.print(toml)
    file.flush
    return Hwaro::Models::Config.load(file.path)
  end
  raise "unreachable"
end

describe "scaffold internal link integrity" do
  scaffolds = scaffold_fixtures

  scaffolds.each do |name, scaffold|
    it "#{name}: every internal link resolves to a generated page or auto-route" do
      files = scaffold.content_files(skip_taxonomies: false)
      known_urls = Set(String).new
      files.each_key { |path| known_urls << content_path_to_url(path) }
      AUTO_ROUTES.each { |route| known_urls << route }

      broken = [] of String
      files.each do |path, body|
        extract_internal_links(body).each do |link|
          next if link =~ ASSET_EXT_RE
          normalized = link.ends_with?("/") ? link : "#{link}/"
          broken << "#{path} → #{link}" unless known_urls.includes?(normalized)
        end
      end

      broken.should eq([] of String)
    end
  end
end

# Multilingual regression: the language-prefixed content the scaffold emits
# rewrites taxonomy links to `/ko/tags/`, `/ko/authors/`, etc. Those resolve
# only if the generated per-language `taxonomies` config enables that taxonomy
# for the language. The per-language lists previously omitted `authors` while
# the global `[[taxonomies]]` set (and the content links) included it, so a
# multilingual blog emitted a dead `/ko/authors/` link.
describe "scaffold multilingual taxonomy config integrity" do
  scaffold_fixtures.each do |name, scaffold|
    it "#{name}: every per-language taxonomies list covers the global taxonomy set" do
      config = load_config_from_string(scaffold.minimal_config_content(false, ["en", "ko"]))

      global_taxonomies = config.taxonomies.map(&.name).to_set
      next if global_taxonomies.empty? # scaffolds without taxonomies (e.g. bare)

      config.languages.each do |lang_code, lang_cfg|
        missing = global_taxonomies - lang_cfg.taxonomies.to_set
        missing.should(
          eq(Set(String).new),
          "language '#{lang_code}' omits taxonomies #{missing.to_a} that the global [[taxonomies]] " \
          "defines; the root would emit them but '#{lang_code}' would not, leaving dead links"
        )
      end
    end
  end
end

# Subpath / base_path regression: a site deployed under a subpath (GitHub Pages
# project pages, e.g. https://user.github.io/repo/) only works when every
# site-internal link is prefixed with `base_url`. The book prev/next nav
# (page.lower/higher.url) and the language switcher (t.url) previously emitted
# bare root-relative URLs like `/chapter-2/` or `/ko/`, which 404 under a
# subpath. Any template href/src that interpolates a page `*.url` value must
# also carry the `base_url` prefix (or an absolute_url/relative_url filter).
describe "scaffold template links are base_url-prefixed (subpath safety)" do
  # Capture every href/src attribute value, then in code keep only the ones
  # that interpolate a dotted `*.url` Jinja expression (e.g. `{{ t.url }}`,
  # `{{ base_url }}{{ p.url }}`). JS string concatenation like `' + r.url + '`
  # is excluded because it lacks `{{`, and its source (search.json) is already
  # base_path-aware.
  attr_re = /(?:href|src)="([^"]*)"/

  scaffold_fixtures.each do |name, scaffold|
    it "#{name}: every templated *.url link carries base_url" do
      templates = scaffold.template_files(skip_taxonomies: false)
      offenders = [] of String
      templates.each do |path, body|
        body.scan(attr_re).each do |m|
          value = m[1]
          next unless value.includes?("{{") && value.includes?(".url")
          next if value.includes?("base_url") ||
                  value.includes?("absolute_url") ||
                  value.includes?("relative_url")
          offenders << "#{path}: #{value}"
        end
      end

      offenders.should(
        eq([] of String),
        "#{name} has site-internal links missing a base_url prefix " \
        "(they would 404 under a subpath deploy): #{offenders.join(", ")}"
      )
    end
  end
end

# Escaping regression: the site logo and the book prev/next arrows interpolate
# author-controlled titles into HTML. Without an `| e` filter a title containing
# `&`, `<`, `>` or `"` breaks the markup (e.g. `Tom & Jerry <Co>` emitted a
# phantom `<Co>` tag). The `<title>` element already escapes, so every other
# `something.title` interpolation in a template must too.
describe "scaffold templates escape interpolated titles" do
  scaffold_fixtures.each do |name, scaffold|
    it "#{name}: no unescaped {{ x.title }} in template HTML" do
      templates = scaffold.template_files(skip_taxonomies: false)
      offenders = [] of String
      templates.each do |path, body|
        # Drop {% raw %}…{% endraw %} example blocks (they show template syntax
        # literally and are never executed).
        sanitized = body.gsub(/\{%\s*raw\s*%\}.*?\{%\s*endraw\s*%\}/m, "")
        # Match dotted title accessors like site.title / page.lower.title, with
        # whatever filters follow, and flag any lacking an escape filter.
        sanitized.scan(/\{\{\s*[\w]+\.[\w.]*title\s*([^}]*)\}\}/) do |m|
          filters = m[1]
          next if filters.includes?("| e") || filters.includes?("escape") || filters.includes?("| upper")
          offenders << "#{path}: #{m[0]}"
        end
      end
      offenders.should(
        eq([] of String),
        "#{name} interpolates author titles into HTML without an `| e` filter " \
        "(breaks markup for titles containing &, <, >, \"): #{offenders.join(", ")}"
      )
    end
  end
end

# Accessibility regression: every scaffold must ship a skip-to-content link as
# an early-focusable bypass (WCAG 2.4.1) pointing at a `<main id="main">` target.
describe "scaffold templates provide a skip-to-content link + #main target" do
  scaffold_fixtures.each do |name, scaffold|
    it "#{name}: header has a #main skip link and a <main id=\"main\">" do
      all = scaffold.template_files(skip_taxonomies: false).values.join("\n")
      all.includes?(%(href="#main")).should(
        be_true, "#{name} ships no skip-to-content link (href=\"#main\")"
      )
      all.matches?(/<main[^>]*\bid="main"/).should(
        be_true, "#{name} has no <main id=\"main\"> skip target"
      )
    end
  end
end
