require "../../support/build_helper"

private alias FMS = Hwaro::Content::FrontMatterSchema

private def schema(fields_toml : String, strict : Bool = false) : Hwaro::Models::ContentSchemaConfig
  load_config("[[content.schema]]\nsections = [\"**\"]\nstrict = #{strict}\n\n#{fields_toml}").content_schema.first
end

# Check `front_matter` (a TOML block) the way the build does for a page with
# no extra beyond its own and the given merged cascade.
private def check(rule, front_matter : String, cascade = {} of String => Hwaro::Models::ExtraValue, file = "content/p.md") : FMS::Result
  source = "+++\n#{front_matter}\n+++\nbody\n"
  extra = Hwaro::Processor::Markdown.parse(source, file)[:extra]
  FMS.check(rule, file, source, extra, cascade)
end

private def messages(result : FMS::Result) : Array(String)
  result.violations.map(&.to_s)
end

describe Hwaro::Content::FrontMatterSchema do
  it "reports a missing required field without a line" do
    rule = schema("[content.schema.fields.author]\ntype = \"string\"\nrequired = true\n")
    messages(check(rule, "title = \"x\"")).should eq([%(content/p.md: field "author": required but missing)])
    check(rule, "title = \"x\"\nauthor = \"me\"").violations.should be_empty
  end

  it "checks each type, keeping int and float apart" do
    rule = schema(<<-TOML)
      [content.schema.fields.s]
      type = "string"
      [content.schema.fields.i]
      type = "int"
      [content.schema.fields.f]
      type = "float"
      [content.schema.fields.b]
      type = "bool"
      [content.schema.fields.a]
      type = "array"
      [content.schema.fields.t]
      type = "table"
      TOML
    check(rule, "s = \"x\"\ni = 1\nf = 1.5\nb = true\na = [\"x\"]\nt = { k = 1 }").violations.should be_empty
    messages(check(rule, "s = 1\ni = 1.0\nf = 1\nb = \"yes\"\na = \"x\"\nt = [1]")).should eq([
      %(content/p.md:2: field "s": expected string, got int),
      %(content/p.md:3: field "i": expected int, got float),
      %(content/p.md:4: field "f": expected float, got int),
      %(content/p.md:5: field "b": expected bool, got string "yes"),
      %(content/p.md:6: field "a": expected array, got string "x"),
      %(content/p.md:7: field "t": expected table, got array),
    ])
  end

  it "accepts for `date` what the date front-matter field accepts" do
    rule = schema("[content.schema.fields.published]\ntype = \"date\"\n[content.schema.fields.\"extra.seen\"]\ntype = \"date\"\n")
    check(rule, "published = 2024-01-02\n[extra]\nseen = 2024-01-02T03:04:05Z").violations.should be_empty
    check(rule, "published = \"2024-01-02 10:00:00\"").violations.should be_empty
    messages(check(rule, "published = \"Sept 1, 2024\"")).should eq([%(content/p.md:2: field "published": expected date, got string "Sept 1, 2024")])
  end

  it "checks enum membership" do
    rule = schema("[content.schema.fields.status]\ntype = \"string\"\nenum = [\"draft\", \"final\"]\n")
    check(rule, "status = \"final\"").violations.should be_empty
    messages(check(rule, "status = \"done\"")).should eq([%(content/p.md:2: field "status": "done" is not one of "draft", "final")])
  end

  it "bounds numbers by value and strings and arrays by length" do
    rule = schema(<<-TOML)
      [content.schema.fields."extra.rating"]
      type = "int"
      min = 1
      max = 5
      [content.schema.fields.summary]
      type = "string"
      min = 3
      [content.schema.fields.tags]
      type = "array"
      max = 2
      TOML
    check(rule, "summary = \"abc\"\ntags = [\"a\"]\n[extra]\nrating = 5").violations.should be_empty
    messages(check(rule, "summary = \"ab\"\ntags = [\"a\", \"b\", \"c\"]\n[extra]\nrating = 0")).should eq([
      %(content/p.md:5: field "extra.rating": 0 is less than the minimum 1),
      %(content/p.md:2: field "summary": length 2 is less than the minimum 3),
      %(content/p.md:3: field "tags": length 3 is greater than the maximum 2),
    ])
  end

  it "reads a name without extra. from an unknown top-level key or [extra]" do
    rule = schema("[content.schema.fields.author]\ntype = \"string\"\nrequired = true\n")
    check(rule, "author = \"me\"").violations.should be_empty
    check(rule, "[extra]\nauthor = \"me\"").violations.should be_empty
  end

  it "counts a cascaded value as present" do
    rule = schema("[content.schema.fields.author]\ntype = \"string\"\nrequired = true\n[content.schema.fields.toc]\ntype = \"bool\"\nrequired = true\n")
    inner = {} of String => Hwaro::Models::ExtraValue
    inner["author"] = "x"
    cascade = {} of String => Hwaro::Models::ExtraValue
    cascade["extra"] = inner
    cascade["toc"] = true
    check(rule, "title = \"x\"", cascade).violations.should be_empty
  end

  it "returns defaults for missing fields only" do
    rule = schema("[content.schema.fields.status]\ntype = \"string\"\ndefault = \"draft\"\nrequired = true\n")
    check(rule, "title = \"x\"").defaults.should eq({"status" => "draft"} of String => Hwaro::Models::SchemaValue)
    check(rule, "status = \"final\"").defaults.should be_empty
    check(rule, "title = \"x\"").violations.should be_empty
  end

  it "flags unknown top-level keys under strict, with a suggestion" do
    rule = schema("[content.schema.fields.author]\ntype = \"string\"\n", strict: true)
    check(rule, "title = \"x\"\nauthor = \"me\"\n[extra]\nanything = 1").violations.should be_empty
    messages(check(rule, "title = \"x\"\nautor = \"me\"\nzzzzzz = 1")).should eq([
      %(content/p.md:3: field "autor": unknown front-matter key — did you mean "author"?),
      %(content/p.md:4: field "zzzzzz": unknown front-matter key (declare it in the schema or move it under [extra])),
    ])
  end

  it "reads YAML and JSON front matter, with lines" do
    rule = schema("[content.schema.fields.rating]\ntype = \"int\"\n")
    yaml = "---\ntitle: x\nrating: 2.5\n---\n"
    FMS.check(rule, "y.md", yaml, {} of String => Hwaro::Models::ExtraValue, {} of String => Hwaro::Models::ExtraValue).violations.map(&.to_s)
      .should eq([%(y.md:3: field "rating": expected int, got float)])
    json = %({\n  "title": "x",\n  "rating": "2"\n}\nbody)
    FMS.check(rule, "j.md", json, {} of String => Hwaro::Models::ExtraValue, {} of String => Hwaro::Models::ExtraValue).violations.map(&.to_s)
      .should eq([%(j.md:3: field "rating": expected int, got string "2")])
  end

  it "counts an explicit false as present: required is met and no default replaces it" do
    rule = schema(<<-TOML)
      [content.schema.fields.flag]
      type = "bool"
      required = true
      [content.schema.fields.toc]
      type = "bool"
      default = true
      [content.schema.fields."extra.featured"]
      type = "bool"
      default = true
      TOML
    result = check(rule, "flag = false\ntoc = false\n[extra]\nfeatured = false")
    result.violations.should be_empty
    result.defaults.should be_empty
  end

  it "sees tags a section cascades through [cascade.taxonomies]" do
    rule = schema("[content.schema.fields.tags]\ntype = \"array\"\nrequired = true\n")
    terms = {} of String => Hwaro::Models::ExtraValue
    terms["tags"] = ["c"]
    cascade = {} of String => Hwaro::Models::ExtraValue
    cascade["taxonomies"] = terms
    check(rule, "title = \"x\"", cascade).violations.should be_empty
  end

  it "applies a `default = false` and lets it satisfy `required`" do
    rule = schema(<<-TOML)
      [content.schema.fields.in_sitemap]
      type = "bool"
      default = false
      [content.schema.fields."extra.featured"]
      type = "bool"
      required = true
      default = false
      TOML
    result = check(rule, "title = \"x\"")
    result.violations.should be_empty
    result.defaults["in_sitemap"].should be_false
    result.defaults["extra.featured"].should be_false
  end

  it "sees any taxonomy given in a [taxonomies] table, own or cascaded" do
    rule = schema("[content.schema.fields.genres]\ntype = \"array\"\nrequired = true\n[content.schema.fields.categories]\ntype = \"array\"\nrequired = true\n")
    check(rule, "title = \"x\"\n[taxonomies]\ngenres = [\"a\"]\ncategories = [\"c\"]").violations.should be_empty
    messages(check(rule, "title = \"x\"\n[taxonomies]\ngenres = [\"a\"]")).should eq([%(content/p.md: field "categories": required but missing)])
    terms = {} of String => Hwaro::Models::ExtraValue
    terms["genres"] = ["g"]
    terms["categories"] = ["c"]
    cascade = {} of String => Hwaro::Models::ExtraValue
    cascade["taxonomies"] = terms
    check(rule, "title = \"x\"", cascade).violations.should be_empty
    messages(check(rule, "title = \"x\"\n[taxonomies]\ngenres = 5\ncategories = [\"c\"]")).first.should contain(%(field "genres": expected array))
  end

  it "points at the top-level or [extra] key, not a nested one of the same name" do
    rule = schema("[content.schema.fields.n]\ntype = \"int\"\n[content.schema.fields.\"extra.rating\"]\ntype = \"int\"\n")
    yaml = "---\nmeta:\n  n: 1\nn: \"x\"\n---\n"
    FMS.check(rule, "y.md", yaml, {} of String => Hwaro::Models::ExtraValue, {} of String => Hwaro::Models::ExtraValue).violations.map(&.to_s)
      .should eq([%(y.md:4: field "n": expected int, got string "x")])
    messages(check(rule, "n = 1\n[meta]\nrating = 1\n[extra]\nrating = \"bad\""))
      .should eq([%(content/p.md:6: field "extra.rating": expected int, got string "bad")])
  end

  it "gives the line of a quoted key with escapes" do
    rule = schema("", strict: true)
    messages(check(rule, "title = \"x\"\n\"q\\\"k\" = 1")).first.should start_with(%(content/p.md:3: field "q\\"k"))
  end

  it "truncates long values in messages" do
    rule = schema("[content.schema.fields.status]\ntype = \"string\"\nenum = [\"a\"]\n[content.schema.fields.n]\ntype = \"int\"\n")
    long = "x" * 5000
    messages(check(rule, "status = \"#{long}\"\nn = \"#{long}\"")).each do |message|
      message.size.should be < 200
      message.should contain("…")
    end
  end

  it "treats NaN as outside min/max" do
    rule = schema("[content.schema.fields.n]\ntype = \"float\"\nmax = 1.0\n")
    messages(check(rule, "n = nan")).should eq([%(content/p.md:2: field "n": NaN is outside the bounds)])
  end

  it "checks huge whole floats without overflowing" do
    rule = schema("[content.schema.fields.n]\ntype = \"float\"\nmax = 1e19\n")
    messages(check(rule, "n = 2e19")).should eq([%(content/p.md:2: field "n": 2.0e+19 is greater than the maximum 1.0e+19)])
  end

  it "points at the [extra] key, not one nested deeper under extra:" do
    rule = schema("[content.schema.fields.\"extra.n\"]\ntype = \"int\"\n")
    yaml = "---\nextra:\n  meta:\n    n: 1\n  n: \"x\"\n---\n"
    FMS.check(rule, "y.md", yaml, {} of String => Hwaro::Models::ExtraValue, {} of String => Hwaro::Models::ExtraValue).violations.map(&.to_s)
      .should eq([%(y.md:5: field "extra.n": expected int, got string "x")])
  end

  it "ignores [table] lines inside a TOML multi-line string" do
    rule = schema("[content.schema.fields.weight]\ntype = \"int\"\n")
    messages(check(rule, "desc = \"\"\"\n[extra]\n\"\"\"\nweight = \"heavy\""))
      .should eq([%(content/p.md:5: field "weight": expected int, got string "heavy")])
  end

  it "fails once with every violation, sorted by file" do
    violations = [
      FMS::Violation.new("content/b.md", 2, "x", "bad"),
      FMS::Violation.new("content/a.md", nil, "y", "required but missing"),
    ]
    err = expect_raises(Hwaro::HwaroError) { FMS.raise_if_any!(violations) }
    err.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
    err.message.should eq(%(2 front-matter schema violations:\n  content/a.md: field "y": required but missing\n  content/b.md:2: field "x": bad))
  end
end

describe "front-matter typo warning vs config-declared keys" do
  # Regression: the parser's "unknown key ... did you mean" warning fired
  # for a key the config declares — a schema field or a taxonomy name.
  it "does not flag schema fields or taxonomy names as typos" do
    log = with_captured_log do
      build_site(
        "title = \"T\"\nbase_url = \"http://localhost\"\n\n[[taxonomies]]\nname = \"tag\"\n\n" \
        "[[content.schema]]\nsections = [\"**\"]\n[content.schema.fields.author]\ntype = \"string\"\n",
        content_files: {"a.md" => "+++\ntitle = \"A\"\nauthor = \"me\"\ntag = [\"x\"]\ntitel = \"t\"\n+++\nx"},
        template_files: {"page.html" => "{{ page.title }}"},
      ) { }
    end
    log.should_not contain("'author'")
    log.should_not contain("'tag'")
    log.should contain("unknown front-matter key 'titel'")
  end
end
