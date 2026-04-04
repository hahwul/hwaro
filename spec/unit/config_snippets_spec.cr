require "../spec_helper"

describe Hwaro::Services::ConfigSnippets do
  describe ".doctor_snippet_for" do
    it "returns snippet for every KNOWN_SECTIONS key" do
      Hwaro::Services::ConfigSnippets::KNOWN_SECTIONS.each_key do |key|
        snippet = Hwaro::Services::ConfigSnippets.doctor_snippet_for(key)
        snippet.should_not be_nil, "Missing doctor_snippet_for(\"#{key}\")"
      end
    end

    it "returns snippet for every KNOWN_SUB_SECTIONS key" do
      Hwaro::Services::ConfigSnippets::KNOWN_SUB_SECTIONS.each_key do |parent, child|
        key = "#{parent}.#{child}"
        snippet = Hwaro::Services::ConfigSnippets.doctor_snippet_for(key)
        snippet.should_not be_nil, "Missing doctor_snippet_for(\"#{key}\")"
      end
    end

    it "returns nil for unknown keys" do
      Hwaro::Services::ConfigSnippets.doctor_snippet_for("nonexistent").should be_nil
    end

    it "returns commented TOML for known sections" do
      snippet = Hwaro::Services::ConfigSnippets.doctor_snippet_for("plugins")
      snippet.should_not be_nil
      snippet.not_nil!.should contain("# [plugins]")
    end
  end

  describe "commented vs uncommented variants" do
    it "plugins: commented version has all values commented out" do
      commented = Hwaro::Services::ConfigSnippets.plugins(commented: true)
      commented.should contain("# [plugins]")
      commented.should contain("# processors")
    end

    it "plugins: uncommented version has active values" do
      uncommented = Hwaro::Services::ConfigSnippets.plugins(commented: false)
      uncommented.should contain("[plugins]")
      uncommented.should contain("processors = [\"markdown\"]")
    end

    it "highlight: commented version has all values commented out" do
      commented = Hwaro::Services::ConfigSnippets.highlight(commented: true)
      commented.should contain("# [highlight]")
      commented.should contain("# enabled")
    end

    it "highlight: uncommented version has active values" do
      uncommented = Hwaro::Services::ConfigSnippets.highlight(commented: false)
      uncommented.should contain("[highlight]")
      uncommented.should contain("enabled = true")
    end

    it "sitemap: commented version has all values commented out" do
      commented = Hwaro::Services::ConfigSnippets.sitemap(commented: true)
      commented.should contain("# [sitemap]")
    end

    it "sitemap: uncommented version has active values" do
      uncommented = Hwaro::Services::ConfigSnippets.sitemap(commented: false)
      uncommented.should contain("[sitemap]")
      uncommented.should contain("enabled = true")
    end

    it "og: both variants contain OpenGraph header" do
      commented = Hwaro::Services::ConfigSnippets.og(commented: true)
      uncommented = Hwaro::Services::ConfigSnippets.og(commented: false)
      commented.should contain("OpenGraph")
      uncommented.should contain("OpenGraph")
    end

    it "feeds: commented version does not contain active section header" do
      commented = Hwaro::Services::ConfigSnippets.feeds(commented: true)
      commented.should contain("# [feeds]")
      commented.should_not contain("\n[feeds]\n")
    end

    it "robots: uncommented version has rules array" do
      uncommented = Hwaro::Services::ConfigSnippets.robots(commented: false)
      uncommented.should contain("[robots]")
      uncommented.should contain("rules = [")
    end

    it "pwa: both variants contain PWA header" do
      commented = Hwaro::Services::ConfigSnippets.pwa(commented: true)
      uncommented = Hwaro::Services::ConfigSnippets.pwa(commented: false)
      commented.should contain("PWA")
      uncommented.should contain("PWA")
    end

    it "amp: both variants contain AMP header" do
      commented = Hwaro::Services::ConfigSnippets.amp(commented: true)
      uncommented = Hwaro::Services::ConfigSnippets.amp(commented: false)
      commented.should contain("AMP")
      uncommented.should contain("AMP")
    end
  end

  describe "non-commented-only snippets" do
    it "content_files returns commented-only snippet" do
      snippet = Hwaro::Services::ConfigSnippets.content_files
      snippet.should contain("Content Files")
      snippet.should contain("# [content.files]")
    end

    it "og_auto_image returns commented-only snippet" do
      snippet = Hwaro::Services::ConfigSnippets.og_auto_image
      snippet.should contain("Auto OG Images")
      snippet.should contain("# [og.auto_image]")
    end

    it "image_processing_lqip returns commented-only snippet" do
      snippet = Hwaro::Services::ConfigSnippets.image_processing_lqip
      snippet.should contain("LQIP")
      snippet.should contain("# [image_processing.lqip]")
    end
  end

  describe "all snippets are non-empty strings" do
    {% for method in ["plugins", "highlight", "og", "sitemap", "robots", "llms",
                      "feeds", "build", "permalinks", "auto_includes", "series",
                      "related", "search", "pagination", "markdown", "assets",
                      "image_processing", "deployment", "pwa", "amp"] %}
      it "{{method.id}}(commented: true) is non-empty" do
        Hwaro::Services::ConfigSnippets.{{method.id}}(commented: true).should_not be_empty
      end

      it "{{method.id}}(commented: false) is non-empty" do
        Hwaro::Services::ConfigSnippets.{{method.id}}(commented: false).should_not be_empty
      end
    {% end %}
  end
end
