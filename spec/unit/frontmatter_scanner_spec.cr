require "../spec_helper"

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
end
