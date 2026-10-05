require "../../spec_helper"

# ext/toml_multiline_string_fix.cr — quote runs inside multi-line strings.
describe "TOML multi-line string lexing (ext/toml_multiline_string_fix)" do
  # Regression: the char after a non-closing quote run was dropped.
  it "keeps the char after embedded quotes" do
    TOML.parse(%(a = """\nsay "hi" now"""))["a"].as_s.should eq(%(say "hi" now))
    TOML.parse(%(a = """ab""cd"""))["a"].as_s.should eq(%(ab""cd))
    TOML.parse(%(a = '''it''s ok'''))["a"].as_s.should eq("it''s ok")
    TOML.parse(%(a = '''say 'hi' now'''))["a"].as_s.should eq("say 'hi' now")
  end

  it "treats up to two quotes before the delimiter as content" do
    TOML.parse(%(a = """a"""""))["a"].as_s.should eq(%(a""))
    TOML.parse(%(a = """a""""))["a"].as_s.should eq(%(a"))
    TOML.parse(%(a = '''a'''''))["a"].as_s.should eq("a''")
    TOML.parse(%(a = """x"""\nb = 1))["b"].as_i.should eq(1)
  end

  it "rejects six quotes" do
    expect_raises(TOML::ParseException) { TOML.parse(%(a = """a"""""")) }
  end
end
