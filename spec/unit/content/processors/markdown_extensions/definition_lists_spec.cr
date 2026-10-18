require "../../../../spec_helper"

describe Hwaro::Content::Processors::MarkdownExtensions do
  describe ".preprocess_definition_lists" do
    it "leaves lines inside raw <script>/<pre>/<style> blocks verbatim" do
      content = "<script>\nvar x = cond\n  ? \"a\"\n  : \"b\";\n</script>\n\n" \
                "<pre>\nkey\n: value\n</pre>\n\n<style>\na\n: b\n</style>\n\nTerm\n: def"
      result = Hwaro::Content::Processors::MarkdownExtensions.preprocess_definition_lists(content)
      result.should contain("  ? \"a\"\n  : \"b\";")
      result.should contain("key\n: value")
      result.should contain("a\n: b")
      result.scan("<dl>").size.should eq(1)
      result.should contain("<dt>Term</dt>\n<dd>def</dd>")
    end
  end
end
