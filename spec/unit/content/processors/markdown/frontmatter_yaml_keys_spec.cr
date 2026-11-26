require "../../../../support/build_helper"

# YAML mapping keys that the YAML reader types as something other than a
# string (`2024:`, `404:`, `true:`, `2024-01-01:`). TOML and JSON keys are
# always strings, so the same front matter written in those formats keeps
# them; YAML used to drop them at the top level, inside `extra` and inside
# `taxonomies`, while nested tables already kept them (`key_string`).
describe "YAML front matter with non-string keys" do
  processor = Hwaro::Content::Processors::Markdown.new

  it "keeps numeric and boolean keys in extra, like TOML" do
    yaml = processor.parse("---\ntitle: y\n2024: year\nflag: 1\nextra:\n  404: missing\n  true: on\n---\nbody\n", "content/y.md")
    toml = processor.parse(%(+++\ntitle = "y"\n2024 = "year"\nflag = 1\n[extra]\n404 = "missing"\ntrue = true\n+++\nbody\n), "content/t.md")
    yaml[:extra].should eq(toml[:extra])
    yaml[:extra]["2024"].should eq("year")
    yaml[:extra]["404"].should eq("missing")
    yaml[:front_matter_keys].should eq(["title", "2024", "flag", "extra"])
  end

  it "names a timestamp key the way nested keys do" do
    result = processor.parse("---\ntitle: y\nextra:\n  2024-01-02: launch\n---\nbody\n", "content/y.md")
    result[:extra]["2024-01-02"].should eq("launch")
  end

  it "keeps a numeric taxonomy name under taxonomies" do
    result = processor.parse("---\ntitle: y\ntaxonomies:\n  2024: [a]\n---\nbody\n", "content/y.md")
    result[:taxonomies]["2024"].should eq(["a"])
  end

  it "lets a [[content.schema]] field see the key page.extra has" do
    rule = load_config("[[content.schema]]\nsections = [\"**\"]\n[content.schema.fields.\"2024\"]\ntype = \"string\"\nrequired = true\n").content_schema.first
    source = "---\ntitle: y\n2024: year\n---\nbody\n"
    extra = processor.parse(source, "content/p.md")[:extra]
    Hwaro::Content::FrontMatterSchema.check(rule, "content/p.md", source, extra, {} of String => Hwaro::Models::ExtraValue).violations.should be_empty
  end
end
