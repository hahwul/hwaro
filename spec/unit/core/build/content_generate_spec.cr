require "../../../spec_helper"

# Specs for `[[content.generate]]` — declarative content generation from
# `site.data` arrays: config parsing/validation, the field-or-template
# evaluation contract (shorthand field names vs Crinja templates over
# `item`), slug hygiene, per-record error messages, the synthetic-markdown
# round trip through the real front-matter parser, and `item_to_extra`.

private BASE_CONFIG = <<-TOML
  title = "Test"
  base_url = "https://example.com"

  TOML

private def generate_config(entry : String) : Hwaro::Models::Config
  load_config(BASE_CONFIG + entry)
end

private alias ContentGenerate = Hwaro::Core::Build::ContentGenerate

private def planner_env : Crinja
  Hwaro::Content::Processors::TemplateEngine.new.env
end

private def data_from_json(json : String) : Hash(String, Crinja::Value)
  value = Hwaro::Utils::CrinjaUtils.parse_data_string(json, "json") ||
          raise "test data did not parse"
  {"products" => value}
end

private PRODUCTS_JSON = <<-JSON
  {"items": [
    {"sku": "Blue Widget 3000", "name": "Blue Widget", "price": 19.99, "released": "2024-01-15", "body_md": "A **blue** widget.", "categories": ["gadgets", "blue things"]},
    {"sku": "red-widget", "name": "Red \\"Deluxe\\" Widget", "price": 24, "released": null, "body_md": "Red.", "categories": "gadgets"}
  ]}
  JSON

private def plan_products(rule_toml : String, json : String = PRODUCTS_JSON) : Array(ContentGenerate::Plan)
  config = generate_config(rule_toml)
  ContentGenerate.plan(config, data_from_json(json), planner_env)
end

private def expect_plan_error(rule_toml : String, json : String = PRODUCTS_JSON) : Hwaro::HwaroError
  err = expect_raises(Hwaro::HwaroError) { plan_products(rule_toml, json) }
  err.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
  err
end

private FULL_RULE = <<-TOML
  [[content.generate]]
  source = "products.items"
  section = "products"
  slug = "sku"
  title = "name"
  body = "body_md"
  date = "released"
  description = "{{ item.name }} — {{ item.price }} USD"
  taxonomies = { tags = "categories" }
  TOML

describe "[[content.generate]] config" do
  it "parses a full rule" do
    config = generate_config(FULL_RULE)
    config.content_generate.size.should eq(1)
    rule = config.content_generate.first
    rule.source.should eq("products.items")
    rule.section.should eq("products")
    rule.slug.should eq("sku")
    rule.title.should eq("name")
    rule.body.should eq("body_md")
    rule.date.should eq("released")
    rule.description.should eq("{{ item.name }} — {{ item.price }} USD")
    rule.taxonomies.should eq({"tags" => "categories"})
  end

  it "rejects a single-table [content.generate]" do
    err = expect_config_error(BASE_CONFIG + "[content.generate]\nsource = \"x\"\nsection = \"s\"\nslug = \"a\"\ntitle = \"b\"")
    err.message.to_s.should contain("array of tables")
  end

  it "requires source, section, slug and title" do
    %w[source section slug title].each do |missing|
      entry = String.build do |io|
        io << "[[content.generate]]\n"
        io << "source = \"products\"\n" unless missing == "source"
        io << "section = \"products\"\n" unless missing == "section"
        io << "slug = \"sku\"\n" unless missing == "slug"
        io << "title = \"name\"\n" unless missing == "title"
      end
      err = expect_config_error(BASE_CONFIG + entry)
      err.message.to_s.should contain("'#{missing}'")
    end
  end

  it "rejects a source that is not a dotted key path" do
    err = expect_config_error(BASE_CONFIG + "[[content.generate]]\nsource = \"pro ducts\"\nsection = \"s\"\nslug = \"a\"\ntitle = \"b\"")
    err.message.to_s.should contain("dotted site.data path")
  end

  it "rejects traversal segments in section and normalizes surrounding slashes" do
    err = expect_config_error(BASE_CONFIG + "[[content.generate]]\nsource = \"products\"\nsection = \"../evil\"\nslug = \"a\"\ntitle = \"b\"")
    err.message.to_s.should contain("'..'")

    config = generate_config("[[content.generate]]\nsource = \"products\"\nsection = \"/shop/items/\"\nslug = \"a\"\ntitle = \"b\"")
    config.content_generate.first.section.should eq("shop/items")
  end

  it "rejects body together with body_template" do
    err = expect_config_error(BASE_CONFIG + "[[content.generate]]\nsource = \"products\"\nsection = \"s\"\nslug = \"a\"\ntitle = \"b\"\nbody = \"c\"\nbody_template = \"d.html\"")
    err.message.to_s.should contain("mutually exclusive")
  end

  it "rejects non-table taxonomies and non-string taxonomy values" do
    expect_config_error(BASE_CONFIG + "[[content.generate]]\nsource = \"products\"\nsection = \"s\"\nslug = \"a\"\ntitle = \"b\"\ntaxonomies = \"tags\"")
    err = expect_config_error(BASE_CONFIG + "[[content.generate]]\nsource = \"products\"\nsection = \"s\"\nslug = \"a\"\ntitle = \"b\"\ntaxonomies = { tags = 3 }")
    err.message.to_s.should contain("taxonomies.tags")
  end
end

describe "ContentGenerate.plan" do
  it "plans one page per record with slugified paths and evaluated fields" do
    plans = plan_products(FULL_RULE)
    plans.size.should eq(2)

    first = plans[0]
    first.path.should eq("products/blue-widget-3000.md")
    first.section.should eq("products")
    first.slug.should eq("blue-widget-3000")
    first.title.should eq("Blue Widget")
    first.origin.should eq("data.products.items")
    first.date_raw.should eq("2024-01-15")
  end

  it "round-trips titles and templated descriptions through the real front-matter parser" do
    plans = plan_products(FULL_RULE)
    parsed = Hwaro::Processor::Markdown.parse(plans[1].markdown, plans[1].path)
    parsed[:title].should eq(%(Red "Deluxe" Widget))
    parsed[:description].should eq("Red \"Deluxe\" Widget — 24 USD")
    parsed[:content].should eq("Red.\n")
    # null `released` must omit the date entirely, not emit date = "".
    parsed[:date].should be_nil
    plans[1].date_raw.should be_nil
  end

  it "parses generated dates with the same leniency as authored front matter" do
    plans = plan_products(FULL_RULE)
    parsed = Hwaro::Processor::Markdown.parse(plans[0].markdown, plans[0].path)
    # Bare dates parse in the same zone authored front matter uses — assert
    # the calendar day, not the zone.
    parsed[:date].not_nil!.to_s("%Y-%m-%d").should eq("2024-01-15")
  end

  it "maps an array taxonomy field to every term and a scalar field to one" do
    plans = plan_products(FULL_RULE)
    blue = Hwaro::Processor::Markdown.parse(plans[0].markdown, plans[0].path)
    blue[:taxonomies]["tags"].should eq(["gadgets", "blue things"])
    red = Hwaro::Processor::Markdown.parse(plans[1].markdown, plans[1].path)
    red[:taxonomies]["tags"].should eq(["gadgets"])
  end

  it "supports template specs with hwaro filters" do
    rule = <<-TOML
      [[content.generate]]
      source = "products.items"
      section = "products"
      slug = "{{ item.sku | slugify }}"
      title = "{{ item.name | upper }}"
      TOML
    plans = plan_products(rule)
    plans[0].slug.should eq("blue-widget-3000")
    plans[0].title.should eq("BLUE WIDGET")
  end

  it "names the rule, record number and available keys on a missing field" do
    rule = FULL_RULE.sub("slug = \"sku\"", "slug = \"skuu\"")
    err = expect_plan_error(rule)
    message = err.message.to_s
    message.should contain(%([[content.generate]] "products.items"))
    message.should contain("record #1")
    message.should contain("missing field 'skuu'")
    message.should contain("available: ")
    message.should contain("sku")
  end

  it "errors on a missing source key, naming what exists" do
    rule = FULL_RULE.sub("products.items", "products.nope")
    err = expect_plan_error(rule)
    err.message.to_s.should contain("site.data.products has no key 'nope'")
    err.message.to_s.should contain("available: items")
  end

  it "errors when the source is not an array" do
    rule = FULL_RULE.sub("source = \"products.items\"", "source = \"products\"")
    err = expect_plan_error(rule)
    err.message.to_s.should contain("must name an array of records")
  end

  it "errors on duplicate slugs, naming both records" do
    json = %({"items": [{"sku": "same", "name": "A"}, {"sku": "SAME", "name": "B"}]})
    rule = "[[content.generate]]\nsource = \"products.items\"\nsection = \"products\"\nslug = \"sku\"\ntitle = \"name\""
    err = expect_plan_error(rule, json)
    err.message.to_s.should contain("record #2")
    err.message.to_s.should contain("record #1")
    err.message.to_s.should contain("products/same.md")
  end

  it "errors when a slug evaluates to nothing slugifiable" do
    json = %({"items": [{"sku": "!!!", "name": "A"}]})
    rule = "[[content.generate]]\nsource = \"products.items\"\nsection = \"products\"\nslug = \"sku\"\ntitle = \"name\""
    err = expect_plan_error(rule, json)
    err.message.to_s.should contain("slugifies to \"\"")
  end

  it "errors when a required field holds null" do
    json = %({"items": [{"sku": null, "name": "A"}]})
    rule = "[[content.generate]]\nsource = \"products.items\"\nsection = \"products\"\nslug = \"sku\"\ntitle = \"name\""
    err = expect_plan_error(rule, json)
    err.message.to_s.should contain("slug evaluated to nothing")
  end

  it "reads nested record fields with dotted shorthand" do
    json = %({"items": [{"meta": {"id": "n-1"}, "name": "A"}]})
    rule = "[[content.generate]]\nsource = \"products.items\"\nsection = \"products\"\nslug = \"meta.id\"\ntitle = \"name\""
    plans = plan_products(rule, json)
    plans[0].path.should eq("products/n-1.md")
  end

  it "errors when body_template cannot be loaded" do
    rule = "[[content.generate]]\nsource = \"products.items\"\nsection = \"products\"\nslug = \"sku\"\ntitle = \"name\"\nbody_template = \"missing.html\""
    err = expect_plan_error(rule)
    err.message.to_s.should contain("body_template \"missing.html\"")
  end

  it "plans nothing for an empty source array" do
    plan_products(FULL_RULE, %({"items": []})).should be_empty
  end

  it "reports a clean error when the source path descends past the record array" do
    # Crinja's Resolver raises ArgumentError (not Crinja::Error) for a
    # string key on an array — unrescued, this crashed the whole build.
    rule = FULL_RULE.sub("products.items", "products.items.name")
    err = expect_plan_error(rule)
    err.message.to_s.should contain("site.data.products.items is an array, not a table")
  end

  it "degrades to zero pages when the source is a skippable [[data.remote]] key left unset" do
    config = generate_config(<<-TOML
      [[data.remote]]
      key = "products"
      url = "https://api.example.com/products.json"
      on_error = "warn-and-skip"

      [[content.generate]]
      source = "products"
      section = "products"
      slug = "sku"
      title = "name"
      TOML
    )
    # The remote fetch was allowed to fail (on_error), so the rule must
    # warn-and-generate-nothing rather than hard-fail the build.
    plans = ContentGenerate.plan(config, {} of String => Crinja::Value, planner_env)
    plans.should be_empty
  end

  it "rejects a slug that resolves to the reserved name index" do
    json = %({"items": [{"sku": "_index", "name": "A"}]})
    rule = "[[content.generate]]\nsource = \"products.items\"\nsection = \"products\"\nslug = \"sku\"\ntitle = \"name\""
    err = expect_plan_error(rule, json)
    err.message.to_s.should contain("reserved name \"index\"")
  end
end

describe "ContentGenerate.authored_twin_exists?" do
  it "detects flat, .markdown and leaf-bundle twins case-sensitively" do
    Dir.mktmpdir do |dir|
      FileUtils.cd(dir) do
        FileUtils.mkdir_p("content/products/widget")
        File.write("content/products/flat.md", "x")
        File.write("content/products/legacy.markdown", "x")
        File.write("content/products/widget/index.md", "x")

        ContentGenerate.authored_twin_exists?("products/flat.md").should be_true
        ContentGenerate.authored_twin_exists?("products/legacy.md").should be_true
        ContentGenerate.authored_twin_exists?("products/widget.md").should be_true
        ContentGenerate.authored_twin_exists?("products/other.md").should be_false
        # Case differences are DIFFERENT paths — File.exists? would fold
        # them on macOS and drop a page Linux CI publishes.
        ContentGenerate.authored_twin_exists?("products/Flat.md").should be_false
      end
    end
  end
end

describe "ContentLister with generated entries" do
  it "applies a section's cascade draft to generated rows (publish-state parity)" do
    Dir.mktmpdir do |dir|
      FileUtils.cd(dir) do
        FileUtils.mkdir_p("content/products")
        File.write("content/products/_index.md", "+++\ntitle = 'P'\n[cascade]\ndraft = true\n+++\n")
        generated = [
          Hwaro::Services::ContentInfo.new(
            path: "products/x.md", title: "X", draft: false, date: nil,
            status: "published", generated_from: "data.products",
          ),
        ]
        lister = Hwaro::Services::ContentLister.new("content", generated)

        # The build drops these pages (cascade draft), so "published" must too.
        lister.list_published.any?(&.generated_from).should be_false
        drafts = lister.list_drafts
        drafts.any? { |info| info.generated_from == "data.products" }.should be_true
      end
    end
  end
end

describe "ContentGenerate.item_to_extra" do
  it "converts nested records into page.extra values" do
    value = Hwaro::Utils::CrinjaUtils.parse_data_string(
      %({"s": "x", "i": 3, "f": 1.5, "b": true, "n": null, "a": [1, "two"], "h": {"k": "v"}}),
      "json",
    ) || raise "parse failed"
    extra = ContentGenerate.item_to_extra(value)
    hash = extra.as(Hash(String, Hwaro::Models::ExtraValue))
    hash["s"].should eq("x")
    hash["i"].should eq(3_i64)
    hash["f"].should eq(1.5)
    hash["b"].should be_true
    hash["n"].should eq("")
    hash["a"].should eq([1_i64, "two"] of Hwaro::Models::ExtraValue)
    hash["h"].should eq({"k" => "v"} of String => Hwaro::Models::ExtraValue)
  end
end
