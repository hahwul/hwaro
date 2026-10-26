require "../../spec_helper"

# The memo stores each tag's parsed arguments, never their values: every
# render must re-evaluate them against its own bindings.
private def first_tag(template : Crinja::Template) : Crinja::AST::TagNode
  template.nodes.children.find(&.is_a?(Crinja::AST::TagNode)).as(Crinja::AST::TagNode)
end

describe "ext/crinja_tag_args_memo" do
  it "re-evaluates memoized if/elif conditions on every render" do
    template = Crinja.new.from_string("{% if n == 1 %}one{% elif n == 2 %}two{% else %}many{% endif %}")

    template.render({"n" => 1}).should eq("one")
    template.render({"n" => 2}).should eq("two")
    template.render({"n" => 3}).should eq("many")
    first_tag(template).__args_expr.should_not be_nil
  end

  it "re-evaluates memoized for-loop arguments on every render" do
    template = Crinja.new.from_string("{% for k, v in pairs if v > floor %}{{ k }}{% endfor %}")
    pairs = {"a" => 1, "b" => 2, "c" => 3}

    template.render({"pairs" => pairs, "floor" => 1}).should eq("bc")
    template.render({"pairs" => pairs, "floor" => 2}).should eq("c")
    first_tag(template).__args_for.should_not be_nil
  end

  it "re-evaluates memoized set, with and do arguments on every render" do
    template = Crinja.new.from_string(
      "{% set a = x * 2, b = x + 1 %}{{ a }},{{ b }}|" \
      "{% with c = x - 1 %}{{ c }}{% endwith %}|" \
      "{% do x + 1 %}.")

    template.render({"x" => 3}).should eq("6,4|2|.")
    template.render({"x" => 5}).should eq("10,6|4|.")
  end

  it "keeps block-form set working" do
    template = Crinja.new.from_string("{% set body %}<{{ x }}>{% endset %}{{ body }}")

    template.render({"x" => 1}).should eq("<1>")
    template.render({"x" => 2}).should eq("<2>")
  end

  it "re-evaluates memoized include arguments on every render" do
    env = Crinja.new
    env.loader = Crinja::Loader::HashLoader.new({
      "a.html" => "A{{ v }}",
      "b.html" => "B{{ v }}",
    })
    template = env.from_string(%({% include name ignore missing %}|{% include "a.html" without context %}))

    template.render({"name" => "a.html", "v" => 1}).should eq("A1|A")
    template.render({"name" => "b.html", "v" => 2}).should eq("B2|A")
    template.render({"name" => "missing.html", "v" => 3}).should eq("|A")
  end

  it "raises a malformed tag on every execution, not only the first" do
    template = Crinja.new.from_string("{% if %}x{% endif %}")

    2.times do
      expect_raises(Crinja::TemplateSyntaxError) { template.render }
    end
  end
end
