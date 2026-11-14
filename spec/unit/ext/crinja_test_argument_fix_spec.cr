require "../../spec_helper"

private def render_test_arg(source : String) : String
  render_crinja(source, {"d" => Crinja::Value.new({Crinja::Value.new("k") => Crinja::Value.new(1)})})
end

describe "Crinja test argument without parentheses" do
  # Expected strings are Jinja2 3.1's output for the same source.
  it "takes one value, so `and` / `or` after it combine whole tests" do
    render_test_arg("{% for i in [1,2,3,4,5,6] %}{% if i is divisibleby 3 and not loop.last %}[{{ i }}]{% endif %}{% endfor %}")
      .should eq("[3]")
    render_test_arg("{{ (false is sameas true or false is sameas false) | lower }}|{{ (2 is eq 2 and 3 is eq 4) | lower }}|{{ (1 is divisibleby 3 or true) | lower }}")
      .should eq("true|false|true")
    render_test_arg(%({{ ("b" is in "abc" and true) | lower }}|{{ ("ab" is eq("a" ~ "b")) | lower }}))
      .should eq("true|true")
  end

  it "keeps attribute and index access on the argument" do
    render_test_arg(%({{ (3 is gt 1 if true else "n") | lower }}|{{ (x is defined) | lower }}|{{ (d.k is eq d["k"]) | lower }}|{{ (d.k is eq 1 == true) | lower }}))
      .should eq("true|false|true|true")
  end

  it "reads a parenthesized argument whole" do
    render_test_arg(%({{ ("/blog/x" is startswith("/blog/") and true) | lower }}|{{ (2 is gt(1 + 3)) | lower }}))
      .should eq("true|false")
  end
end

# The lines the template's parse logs about a bare argument whose reading
# changed in 1.0 (src/ext/crinja_test_argument_fix.cr).
private def bare_test_arg_warnings(source : String, filename : String? = "templates/page.html") : Array(String)
  Hwaro::Content::Processors::TemplateEngine.clear_load_data_cache
  env = Hwaro::Content::Processors::TemplateEngine.new.env
  with_captured_log { Crinja::Template.new(source, env, "page", filename) }.lines.select(&.includes?(" is read as "))
end

describe "Crinja test argument followed by an operator" do
  it "warns once per location, naming the file and line and both readings" do
    source = %(<p>\n{% if page.url is startswith "/blog" ~ "/" %}x{% endif %}{{ 3 is divisibleby 1 + 2 }}\n)
    warnings = bare_test_arg_warnings(source)
    warnings.size.should eq(2)
    warnings[1].should contain(%(templates/page.html:2: '3 is divisibleby 1 + 2' is read as '(3 is divisibleby 1) + 2'; write '3 is divisibleby(1 + 2)'))
    warnings[0].should contain(%(templates/page.html:2: 'page.url is startswith "/blog" ~ "/"' is read as '(page.url is startswith "/blog") ~ "/"'; ) +
                               %(write 'page.url is startswith("/blog" ~ "/")' to test against "/blog" ~ "/", or '(page.url is startswith "/blog") ~ "/"' to keep this reading.))
  end

  it "covers each operator that changed meaning, in `{{ }}` and in tags" do
    ops = ["~ 1", "+ 1", "- 1", "* 1", "/ 1", "// 1", "% 1", "| lower", "is sameas true"]
    ops.each do |op|
      bare_test_arg_warnings(%({{ 4 is eq 2 #{op} }})).size.should eq(1)
      bare_test_arg_warnings(%({% set a = 4 is eq 2 #{op} %})).size.should eq(1)
      bare_test_arg_warnings(%({% for i in [1] if i is not eq 2 #{op} %}{% endfor %})).size.should eq(1)
    end
  end

  it "does not warn for and/or/not/in/comparisons, a parenthesized argument or a misread inside raw" do
    bare_test_arg_warnings(<<-JINJA).should be_empty
      {% if loop.index is divisibleby 3 and not loop.last or x is eq 1 %}{% endif %}
      {{ 4 is divisibleby 2 == true }}{{ x is eq 1 != y }}{{ x is eq 1 < 2 }}{{ x is eq 1 in [true] }}
      {{ x is startswith("/blog" ~ "/") }}{{ x is startswith("a") ~ "b" }}{{ x is defined ~ "b" }}
      {{ "y" if x is eq 1 else "n" }}{{ x is eq -1 }}{{ (x is eq 1) ~ "b" }}
      {% raw %}{{ x is eq a ~ b }}{% endraw %}
      JINJA
  end

  it "locates the test after multi-byte text and across lines, and names an anonymous template" do
    warnings = bare_test_arg_warnings("한글 ünï\n{{\n  x is\n   eq a\n   ~ b }}", nil)
    warnings.should eq(["[WARN] page:3: 'x is eq a ~ b' is read as '(x is eq a) ~ b'; write 'x is eq(a ~ b)' to test against a ~ b, or '(x is eq a) ~ b' to keep this reading."])
  end

  it "leaves the output as it was" do
    render_test_arg(%({{ 3 is divisibleby 1 + 2 }}|{{ "/x" is startswith "/blog" ~ "/" }})).should eq("true2|false/")
  end
end
