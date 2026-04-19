require "../spec_helper"
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

describe "scaffold internal link integrity" do
  scaffolds = {
    "blog"      => Hwaro::Services::Scaffolds::Blog.new,
    "blog_dark" => Hwaro::Services::Scaffolds::BlogDark.new,
    "docs"      => Hwaro::Services::Scaffolds::Docs.new,
    "docs_dark" => Hwaro::Services::Scaffolds::DocsDark.new,
    "book"      => Hwaro::Services::Scaffolds::Book.new,
    "book_dark" => Hwaro::Services::Scaffolds::BookDark.new,
    "simple"    => Hwaro::Services::Scaffolds::Simple.new,
    "bare"      => Hwaro::Services::Scaffolds::Bare.new,
  }

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
