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

  # CRLF files (git autocrlf, Windows editors): the newline after the opening
  # delimiter is trimmed, a line-ending backslash continues before CRLF, and
  # CRLF reads as LF.
  describe "CRLF line endings" do
    it "trims the newline after the opening delimiter" do
      TOML.parse(%(a = """\r\nline one\r\nline two"""))["a"].as_s.should eq("line one\nline two")
      TOML.parse(%(a = '''\r\nline one\r\nline two'''))["a"].as_s.should eq("line one\nline two")
    end

    it "treats a line-ending backslash before CRLF as a continuation" do
      TOML.parse(%(a = """\r\nline one \\\r\n   continued\r\n"""))["a"].as_s.should eq("line one continued\n")
      TOML.parse(%(a = """x \\\r\n\r\n  y"""))["a"].as_s.should eq("x y")
    end

    it "keeps LF documents unchanged and still reads the next key" do
      TOML.parse(%(a = """\nx\ny"""\r\nb = 1))["a"].as_s.should eq("x\ny")
      TOML.parse(%(a = """\r\nx\r\n"""\r\nb = 1))["b"].as_i.should eq(1)
    end
  end
end
