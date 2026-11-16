require "../../spec_helper"
require "../../../src/content/processors/syntax_highlighter"

# ext/tartrazine_quantifier_fix.cr — Pygments' `{,n}` quantifier is spelled
# `{0,n}` before PCRE2 sees it, so every PCRE2 version (10.42 in the official
# Crystal macOS tarball, 10.43+ elsewhere) highlights the same way; Chroma's
# `\uhhhh` and `\b?`, which no PCRE2 compiles, are spelled the PCRE2 way.

private def portable(pattern : String) : String
  BytesRegex.hwaro_portable_pattern(pattern)
end

describe "Tartrazine pattern portability (ext/tartrazine_quantifier_fix)" do
  it "rewrites {,n} to {0,n}" do
    portable("^(\\s*)([rRuUbB]{,2})(\"\"\")").should eq("^(\\s*)([rRuUbB]{0,2})(\"\"\")")
    portable("(R)(\")([^\\\\()\\s]{,16})(\\()").should eq("(R)(\")([^\\\\()\\s]{0,16})(\\()")
    portable("a{,2}b{,10}").should eq("a{0,2}b{0,10}")
  end

  it "leaves braces that are not a {,n} quantifier alone" do
    [
      "a{2,}", "a{1,3}", "a{,}", "a{,x}", "a{,2", "x{ ,2}",
      "\\{,2}",     # escaped brace
      "\\\\\\{,2}", # escaped backslash, then an escaped brace
      "[{,2}]",     # inside a character class
      "[^{,2}]", "[]{,2}]", "[^]{,2}]",
      "[\\]{,2}]",       # escaped ] does not close the class
      "[[:alpha:]{,2}]", # POSIX class inside a bracket expression
      "\\Q{,2}\\E",      # quoted literal
      "\\x{41}\\p{L}",
    ].each do |pattern|
      portable(pattern).should eq(pattern)
    end
  end

  it "rewrites a quantifier after a class, an escape or a \\Q literal" do
    portable("[a-z]{,3}").should eq("[a-z]{0,3}")
    portable("[[:alpha:]]{,3}").should eq("[[:alpha:]]{0,3}")
    portable("\\{{,2}").should eq("\\{{0,2}")
    portable("\\Qx\\E{,2}").should eq("\\Qx\\E{0,2}")
    portable("é{,2}한").should eq("é{0,2}한")
  end

  it "spells \\uhhhh as \\x{hhhh}, which PCRE2 accepts" do
    portable("\\b(Set|Prop)[\\u2080-\\u2089]*\\b").should eq("\\b(Set|Prop)[\\x{2080}-\\x{2089}]*\\b")
    portable("\\u03BB|\\u2200").should eq("\\x{03BB}|\\x{2200}")
    BytesRegex::Regex.new("[^\\u0000-\\u007F]+", anchored: true).match("λ→".to_slice).size.should eq(1)
  end

  it "groups a quantified assertion, which PCRE2 cannot repeat bare" do
    portable("\\b([<>]=|<>|<|>)\\b?").should eq("\\b([<>]=|<>|<|>)(?:\\b)?")
    portable("a\\B*\\A+").should eq("a(?:\\B)*(?:\\A)+")
    BytesRegex::Regex.new("\\b(<>)\\b?", anchored: true).match("a<>b".to_slice, 1).size.should eq(2)
  end

  it "leaves escapes that are not \\uhhhh or a quantified assertion alone" do
    [
      "\\\\u2080",         # escaped backslash, then a literal u
      "\\u20", "\\u20G0",  # not four hex digits
      "\\Q\\u2080\\b?\\E", # quoted literal
      "[\\b?]",            # \b in a class is a backspace
      "\\b", "\\b{2}", "\\d?", "\\x{2080}",
    ].each do |pattern|
      portable(pattern).should eq(pattern)
    end
  end

  it "matches {,n} as a quantifier on every PCRE2" do
    BytesRegex::Regex.new("a{,2}b", anchored: true).match("aab".to_slice).size.should eq(1)
  end

  it "classifies a Python docstring as a doc string" do
    html = Hwaro::Content::Processors::ServerHighlighter.highlight(%(def f():\n    """Doc."""\n), "python")
    html.to_s.should contain(%(<span class="hljs-doctag">&quot;&quot;&quot;Doc.&quot;&quot;&quot;</span>))
  end
end
