require "../../spec_helper"

private def render_cond(source : String) : String
  Crinja.new.from_string(source).render({
    "l" => Crinja::Value.new([3, 1, 2].map { |i| Crinja::Value.new(i) }),
    "t" => Crinja::Value.new("T"),
  })
end

# Expected strings are Jinja2 3.1's output for the same source.
describe "Crinja conditional expression" do
  it "picks a branch" do
    render_cond("{{ 'yes' if true else 'no' }}|{{ 'yes' if 0 else 'no' }}|[{{ 'yes' if false }}]").should eq("yes|no|[]")
    render_cond("{{ 'a' if false else 'b' if false else 'c' }}").should eq("c")
    render_cond("{% set v = '' if false else 'fallback' %}{{ v }}").should eq("fallback")
  end

  it "evaluates only the chosen branch" do
    render_cond("{{ missing.deep if missing else 'safe' }}").should eq("safe")
  end

  it "binds looser than filters, tests and operators" do
    render_cond("{{ 1 if true else 2 + 10 }}|{{ (1 if true else 2) + 10 }}").should eq("1|11")
    render_cond("{{ t | lower if t else 'none' }}|{{ t if t is defined else '' }}").should eq("t|T")
  end

  it "leaves a for loop's `if` filter alone" do
    render_cond("{% for i in l if i > 1 %}{{ i }}{% endfor %}").should eq("32")
    render_cond("{% for i in l | sort if i > 1 %}{{ i }}{% endfor %}").should eq("23")
    render_cond("{% for i in (l if true else []) if i > 1 %}{{ 'odd' if i % 2 else 'even' }} {% endfor %}").should eq("odd even ")
  end

  it "does not pull an inline if into a test argument written without parentheses" do
    render_cond(%({{ 4 is divisibleby 2 if false else "no" }})).should eq("no")
    render_cond(%({{ 4 is eq 4 if false else "no" }})).should eq("no")
    render_cond(%({{ 4 is divisibleby 2 if true else "no" }})).should eq("true")
    render_cond(%({{ 4 is defined }}|{{ "x" if true else "y" }})).should eq("true|x")
  end
end
