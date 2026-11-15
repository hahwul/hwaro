require "../../spec_helper"
require "../../../src/content/processors/syntax_highlighter"

# ext/tartrazine_quantifier_fix.cr — Pygments' `{,n}` quantifier is spelled
# `{0,n}` before PCRE2 sees it, so every PCRE2 version (10.42 in the official
# Crystal macOS tarball, 10.43+ elsewhere) highlights the same way.

private def portable(pattern : String) : String
  BytesRegex.hwaro_portable_quantifiers(pattern)
end

describe "Tartrazine {,n} quantifier (ext/tartrazine_quantifier_fix)" do
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

  it "matches {,n} as a quantifier on every PCRE2" do
    BytesRegex::Regex.new("a{,2}b", anchored: true).match("aab".to_slice).size.should eq(1)
  end

  it "classifies a Python docstring as a doc string" do
    html = Hwaro::Content::Processors::ServerHighlighter.highlight(%(def f():\n    """Doc."""\n), "python")
    html.to_s.should contain(%(<span class="hljs-doctag">&quot;&quot;&quot;Doc.&quot;&quot;&quot;</span>))
  end
end
