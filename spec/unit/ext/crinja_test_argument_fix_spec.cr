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
