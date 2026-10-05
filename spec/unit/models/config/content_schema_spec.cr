require "../../../spec_helper"

private SCHEMA_HEAD = <<-TOML
  [[content.schema]]
  sections = ["posts", "docs/**"]

  TOML

describe "[[content.schema]] config" do
  it "is empty by default" do
    load_config("title = \"x\"\n").content_schema.should be_empty
  end

  it "loads sections, strict and fields in declaration order" do
    config = load_config(<<-TOML)
      [[content.schema]]
      sections = "posts"
      strict = true

      [content.schema.fields.author]
      type = "string"
      required = true

      [content.schema.fields.status]
      type = "string"
      enum = ["draft", "final"]
      default = "draft"

      [content.schema.fields."extra.rating"]
      type = "int"
      min = 1
      max = 5
      TOML
    schema = config.content_schema.first
    schema.sections.should eq(["posts"])
    schema.strict.should be_true
    schema.fields.map(&.name).should eq(["author", "status", "extra.rating"])
    schema.fields[0].required.should be_true
    schema.fields[1].default.should eq("draft")
    schema.fields[1].enum_values.should eq(["draft", "final"] of Hwaro::Models::SchemaValue)
    schema.fields[2].extra_key.should eq("rating")
    schema.fields[2].min.should eq(1.0)
    schema.fields[2].max.should eq(5.0)
  end

  it "matches section globs, `X/**` including X itself, and \"\" for the root" do
    config = load_config(SCHEMA_HEAD)
    schema = config.content_schema.first
    schema.matches?("posts").should be_true
    schema.matches?("posts/2024").should be_false
    schema.matches?("docs").should be_true
    schema.matches?("docs/guide/deep").should be_true
    schema.matches?("").should be_false
    load_config("[[content.schema]]\nsections = [\"\"]\n").content_schema.first.matches?("").should be_true
  end

  describe "malformed schemas are config errors" do
    it "rejects an unknown type with a suggestion" do
      err = expect_config_error(SCHEMA_HEAD + "[content.schema.fields.a]\ntype = \"strng\"\n")
      err.message.to_s.should contain("unknown type 'strng'")
      err.message.to_s.should contain("Did you mean 'string'?")
    end

    it "rejects a missing type" do
      expect_config_error(SCHEMA_HEAD + "[content.schema.fields.a]\nrequired = true\n").message.to_s.should contain("missing 'type'")
    end

    it "rejects an enum on a type that cannot carry one, and mixed enum values" do
      expect_config_error(SCHEMA_HEAD + "[content.schema.fields.a]\ntype = \"bool\"\nenum = [true]\n")
        .message.to_s.should contain("'enum' applies to string, int and float")
      expect_config_error(SCHEMA_HEAD + "[content.schema.fields.a]\ntype = \"int\"\nenum = [\"two\"]\n")
        .message.to_s.should contain("enum value \"two\" is a string, not a int")
    end

    it "rejects min greater than max, and bounds on a type without them" do
      expect_config_error(SCHEMA_HEAD + "[content.schema.fields.a]\ntype = \"int\"\nmin = 5\nmax = 1\n")
        .message.to_s.should contain("min (5) is greater than max (1)")
      expect_config_error(SCHEMA_HEAD + "[content.schema.fields.a]\ntype = \"bool\"\nmin = 1\n")
        .message.to_s.should contain("'min' applies to")
    end

    it "rejects unknown keys in a field table with a suggestion" do
      err = expect_config_error(SCHEMA_HEAD + "[content.schema.fields.a]\ntype = \"string\"\nrequird = true\n")
      err.message.to_s.should contain("unknown key 'requird'")
      err.message.to_s.should contain("Did you mean 'required'?")
    end

    it "rejects unknown keys in the schema entry, and a missing sections" do
      expect_config_error("[[content.schema]]\nsections = [\"\"]\nstrickt = true\n").message.to_s.should contain("Did you mean 'strict'?")
      expect_config_error("[[content.schema]]\nstrict = true\n").message.to_s.should contain("missing 'sections'")
      expect_config_error("[content.schema]\nsections = [\"\"]\n").message.to_s.should contain("must be an array of tables")
    end

    it "rejects a default whose type does not match, or that the enum/bounds reject" do
      expect_config_error(SCHEMA_HEAD + "[content.schema.fields.a]\ntype = \"int\"\ndefault = \"x\"\n")
        .message.to_s.should contain("default \"x\" does not satisfy the field: expected int, got string")
      expect_config_error(SCHEMA_HEAD + "[content.schema.fields.a]\ntype = \"float\"\ndefault = 1\n")
        .message.to_s.should contain("expected float, got int")
      expect_config_error(SCHEMA_HEAD + "[content.schema.fields.a]\ntype = \"string\"\nenum = [\"x\"]\ndefault = \"y\"\n")
        .message.to_s.should contain("is not one of")
    end

    it "rejects a default on a known field resolved during parsing" do
      expect_config_error(SCHEMA_HEAD + "[content.schema.fields.slug]\ntype = \"string\"\ndefault = \"x\"\n")
        .message.to_s.should contain("'slug' is resolved while the page is parsed")
    end

    it "rejects names that nest deeper than extra.<key>" do
      expect_config_error(SCHEMA_HEAD + "[content.schema.fields.\"extra.a.b\"]\ntype = \"int\"\n")
        .message.to_s.should contain("nothing nests deeper")
      expect_config_error(SCHEMA_HEAD + "[content.schema.fields.extra.rating]\ntype = \"int\"\n")
        .message.to_s.should contain("quoting the dotted name")
    end
  end
end
