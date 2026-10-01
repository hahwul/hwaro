require "../../spec_helper"

describe Hwaro::Utils::FrontmatterScanner do
  describe ".find_json_end" do
    it "returns end offset for a simple balanced object" do
      content = %({"title": "hello"}\n\nbody)
      Hwaro::Utils::FrontmatterScanner.find_json_end(content).should eq(18)
    end

    it "handles nested objects" do
      content = %({"a": {"b": {"c": 1}}, "d": 2}rest)
      end_idx = Hwaro::Utils::FrontmatterScanner.find_json_end(content).not_nil!
      content[0, end_idx].should eq(%({"a": {"b": {"c": 1}}, "d": 2}))
    end

    it "ignores braces inside string literals" do
      content = %({"tpl": "a {b} c {d}"}remainder)
      end_idx = Hwaro::Utils::FrontmatterScanner.find_json_end(content).not_nil!
      content[0, end_idx].should eq(%({"tpl": "a {b} c {d}"}))
    end

    it "respects escaped quotes inside strings" do
      content = %({"q": "he said \\"hi\\"}"}rest)
      end_idx = Hwaro::Utils::FrontmatterScanner.find_json_end(content).not_nil!
      content[0, end_idx].should eq(%({"q": "he said \\"hi\\"}"}))
    end

    it "handles escaped backslash at end of string" do
      content = %({"k": "a\\\\"}tail)
      end_idx = Hwaro::Utils::FrontmatterScanner.find_json_end(content).not_nil!
      content[0, end_idx].should eq(%({"k": "a\\\\"}))
    end

    it "returns nil when braces never balance" do
      content = %({"a": {"b": 1})
      Hwaro::Utils::FrontmatterScanner.find_json_end(content).should be_nil
    end

    it "returns nil for empty input" do
      Hwaro::Utils::FrontmatterScanner.find_json_end("").should be_nil
    end

    it "returns nil when content does not start with {" do
      Hwaro::Utils::FrontmatterScanner.find_json_end(%( {"a":1})).should be_nil
      Hwaro::Utils::FrontmatterScanner.find_json_end("---\ntitle: t\n---").should be_nil
      Hwaro::Utils::FrontmatterScanner.find_json_end("hello").should be_nil
    end

    it "handles an empty object" do
      Hwaro::Utils::FrontmatterScanner.find_json_end("{}rest").should eq(2)
    end

    it "returns end of first top-level object and ignores trailing content" do
      content = %({"a":1}\n{"b":2})
      end_idx = Hwaro::Utils::FrontmatterScanner.find_json_end(content).not_nil!
      content[0, end_idx].should eq(%({"a":1}))
    end

    it "handles multi-byte UTF-8 inside strings" do
      content = %({"title": "한글 { test }"}tail)
      end_idx = Hwaro::Utils::FrontmatterScanner.find_json_end(content).not_nil!
      # offset is byte-based; decode should still be valid
      content.byte_slice(0, end_idx).should eq(%({"title": "한글 { test }"}))
    end

    it "returns nil when an unterminated string consumes the closing brace" do
      content = %({"k": "oops)
      Hwaro::Utils::FrontmatterScanner.find_json_end(content).should be_nil
    end
  end

  # The build only reads a leading `{` as JSON front matter when a key (`"`)
  # or `}` follows it; a page opening with a shortcode, a Jinja tag or an
  # attribute list has no front matter. The read-only tools must agree.
  describe ".detect / .strip_frontmatter JSON intent" do
    it "does not treat a leading shortcode or Jinja tag as JSON front matter" do
      ["{{ youtube(id=\"abc\") }}\n\nBody.\n", "{% raw %}x{% endraw %}\n", "{:.lead}\nBody\n", "{ not json }\nBody\n"].each do |content|
        Hwaro::Utils::FrontmatterScanner.json_start?(content).should be_false
        Hwaro::Utils::FrontmatterScanner.detect(content).should be_nil
        Hwaro::Utils::FrontmatterScanner.strip_frontmatter(content).should eq(content)
      end
    end

    it "still detects JSON front matter opening with a key or an empty object" do
      Hwaro::Utils::FrontmatterScanner.detect(%({\n  "title": "T"\n}\nBody)).should eq({:json, %({\n  "title": "T"\n})})
      Hwaro::Utils::FrontmatterScanner.detect("{}\nBody").should eq({:json, "{}"})
      Hwaro::Utils::FrontmatterScanner.strip_frontmatter(%({"title": "T"}\nBody)).should eq("\nBody")
    end
  end

  # The build only reads a leading `---` pair as front matter when the block
  # is a mapping, empty/comment-only, or broken-but-key-shaped; anything else
  # is body text opening with a thematic break.
  describe ".yaml_front_matter? / .strip_frontmatter thematic breaks" do
    it "keeps prose between two thematic breaks as body text" do
      content = "---\n\n*Note*: imported from an old blog.\n\n---\n\nBody text here.\n"
      Hwaro::Utils::FrontmatterScanner.yaml_front_matter?("\n*Note*: imported from an old blog.\n\n").should be_false
      Hwaro::Utils::FrontmatterScanner.strip_frontmatter(content).should eq(content)
      list = "---\n- one\n- two\n---\nBody\n"
      Hwaro::Utils::FrontmatterScanner.strip_frontmatter(list).should eq(list)
    end

    it "still strips mappings, empty blocks and broken key-shaped blocks" do
      Hwaro::Utils::FrontmatterScanner.strip_frontmatter("---\ntitle: T\n---\nBody\n").should eq("Body\n")
      Hwaro::Utils::FrontmatterScanner.strip_frontmatter("---\n# only a comment\n---\nBody\n").should eq("Body\n")
      Hwaro::Utils::FrontmatterScanner.yaml_front_matter?("title: [unclosed\n").should be_true
    end
  end
end
