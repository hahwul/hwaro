require "../spec_helper"
require "../../src/models/config"
require "../../src/services/scaffolds/blog"
require "../../src/services/scaffolds/blog_dark"
require "../../src/services/scaffolds/docs"
require "../../src/services/scaffolds/docs_dark"
require "../../src/services/scaffolds/book"
require "../../src/services/scaffolds/book_dark"
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
  links
end

private def scaffold_fixtures
  {
    "blog"      => Hwaro::Services::Scaffolds::Blog.new,
    "blog_dark" => Hwaro::Services::Scaffolds::BlogDark.new,
    "docs"      => Hwaro::Services::Scaffolds::Docs.new,
    "docs_dark" => Hwaro::Services::Scaffolds::DocsDark.new,
    "book"      => Hwaro::Services::Scaffolds::Book.new,
    "book_dark" => Hwaro::Services::Scaffolds::BookDark.new,
    "simple"    => Hwaro::Services::Scaffolds::Simple.new,
    "bare"      => Hwaro::Services::Scaffolds::Bare.new,
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
