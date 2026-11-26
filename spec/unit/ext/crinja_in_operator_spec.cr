require "../../spec_helper"
require "../../../src/ext/crinja_in_operator"

private def render_in(source : String, vars = {} of String => Crinja::Value) : String
  Crinja.new.from_string(source).render(vars)
end

describe "Crinja `in` / `not in` operators" do
  it "tests array membership by element, not substring" do
    vars = {"tags" => Crinja.value(["C++", "Crystal"])}
    render_in(%({{ "Crystal" in tags }}|{{ "C" in tags }}|{{ "Go" not in tags }}), vars).should eq("true|false|true")
  end

  it "parses the documented if-tag form" do
    vars = {"tags" => Crinja.value(["tutorial"])}
    render_in(%({% if "tutorial" in tags %}yes{% endif %}), vars).should eq("yes")
  end

  it "tests substrings for strings and keys for mappings" do
    vars = {"m" => Crinja.value({"a" => 1})}
    render_in(%({{ "ab" in "cab" }}|{{ "a" in m }}|{{ 1 in m }}|{{ "z" not in "cab" }}), vars).should eq("true|true|false|true")
  end

  it "binds looser than filters and leaves for-loops alone" do
    vars = {"xs" => Crinja.value(["A", "b"])}
    render_in(%({{ "a" in xs | map("lower") | list }}|{% for x in xs if x in ["b"] %}{{ x }}{% endfor %}), vars).should eq("true|b")
  end

  it "is false for an undefined container, like Jinja" do
    render_in(%({{ "x" in missing }}|{{ "x" not in missing }})).should eq("false|true")
  end

  it "gives not lower precedence than comparisons, like Jinja" do
    vars = {"tags" => Crinja.value(["b"])}
    render_in(%({{ not "a" in tags }}|{{ not 1 == 2 }}|{{ not false and true }}|{% if not "b" in tags %}x{% else %}y{% endif %}), vars).should eq("true|true|true|y")
  end

  it "rejects a non-iterable right operand at render time" do
    expect_raises(Crinja::TypeError) { render_in(%({{ 1 in 2 }})) }
  end
end

describe "Crinja `in` test" do
  # `x is in(seq)` raised a bare Exception naming the argument's debug form
  # for an undefined, none or numeric seq; Jinja2's test is `x in seq`.
  it "is false for an undefined sequence, as the operator is" do
    vars = {"page" => Crinja.value({"extra" => {} of String => String})}
    render_in(%({{ "a" is in(page.extra.featured) }}|{{ "a" is in(missing) }}|{{ "a" is not in missing }}), vars).should eq("false|false|true")
  end

  it "rejects a non-iterable sequence with the operator's TypeError" do
    expect_raises(Crinja::TypeError, "argument of `in` is not iterable") { render_in(%({{ "a" is in(none) }})) }
    expect_raises(Crinja::TypeError, "argument of `in` is not iterable") { render_in(%({{ 1 is in(5) }})) }
  end

  it "keeps membership by element, substring and key" do
    vars = {"tags" => Crinja.value(["a", "b"]), "m" => Crinja.value({"k" => 1})}
    render_in(%({{ "a" is in(tags) }}|{{ "x" is in(tags) }}|{{ "b" is in("abc") }}|{{ "k" is in(m) }}|{{ tags | select("in", ["b"]) | join }}), vars).should eq("true|false|true|true|b")
  end
end
