require "../../../../spec_helper"
require "../../../../support/build_helper"

# `extract_taxonomies` collects every top-level list, because the parser
# does not know which taxonomies the site configures. It used to warn
# "`sizes` has a non-string value (1.5) — ignored" for any of them, so plain
# page data (`sizes = [1.5, 2.5]`, a `[[gallery]]` table array) drew a
# warning claiming the value was dropped — while page.extra kept it whole.
describe "front matter taxonomy-term warnings" do
  processor = Hwaro::Content::Processors::Markdown.new
  source = "+++\ntitle = \"x\"\nsizes = [1.5, 2.5]\ncategories = [1.5]\n[[gallery]]\nsrc = \"a.jpg\"\n+++\nbody\n"

  it "stays quiet about non-string members of a list that is not a taxonomy" do
    log = with_captured_log { processor.parse(source, "content/p.md", Set{"tags", "categories"}) }
    log.should_not contain("`sizes`")
    log.should_not contain("`gallery`")
    log.should contain("content/p.md: `categories` has a non-string value (1.5)")
  end

  # Which lists are taxonomies comes from config, so these two go through
  # the build: its parse passes the declared keys AND the taxonomy names.
  it "still warns for a configured taxonomy" do
    log = with_captured_log do
      build_site(BASIC_CONFIG + "\n[[taxonomies]]\nname = \"sizes\"\n", content_files: {"p.md" => source}) { }
    end
    log.should contain("content/p.md: `sizes` has a non-string value (1.5)")
    log.should_not contain("`gallery`")
  end

  # A `[[content.schema]]` field name is a declared key too, but not a
  # taxonomy: its list is page data.
  it "stays quiet for a declared schema field that is not a taxonomy" do
    config = BASIC_CONFIG + "\n[[content.schema]]\nsections = [\"**\"]\n[content.schema.fields.sizes]\ntype = \"array\"\n"
    log = with_captured_log { build_site(config, content_files: {"p.md" => source}) { } }
    log.should_not contain("`sizes`")
    log.should contain("content/p.md: `categories` has a non-string value (1.5)")
  end

  it "keeps the data in page.extra either way" do
    result = processor.parse(source, "content/p.md", Set{"tags"})
    result[:extra]["sizes"].should eq([1.5, 2.5].map(&.as(Hwaro::Models::ExtraValue)))
    result[:extra]["gallery"].as(Array).size.should eq(1)
  end
end
