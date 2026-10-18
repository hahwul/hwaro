require "../../spec_helper"

private def render_call(source : String) : String
  Crinja.new.from_string(source).render
end

# Expected strings are Jinja2 3.1's output for the same source.
describe "Crinja `caller` in a {% call %} block" do
  it "is a truthy, defined variable inside the called macro" do
    render_call(%({% macro m() %}{{ caller() if caller else "none" }}{% endmacro %}{% call m() %}!{% endcall %}|{{ m() }}))
      .should eq("!|none")
    render_call(%({% macro m() %}{% if caller is defined %}[{{ caller() }}]{% endif %}{% endmacro %}{% call m() %}x{% endcall %}|{{ m() }}))
      .should eq("[x]|")
  end

  it "does not outlive the call" do
    expect_raises(Crinja::Error, /caller/) do
      render_call(%({% macro m() %}{{ caller() }}{% endmacro %}{% call m() %}!{% endcall %}{{ m() }}))
    end
  end

  it "keeps caller arguments and the call site's variables" do
    render_call(%({% set v = "V" %}{% macro m() %}{{ caller(5) }}{% endmacro %}{% call(x) m() %}{{ v }}{{ x }}{% endcall %}))
      .should eq("V5")
  end

  it "calls a macro imported under a namespace" do
    env = Crinja.new
    env.loader = Crinja::Loader::HashLoader.new({
      "forms.html" => %({% macro box(t) %}<div>{{ t }}:{{ caller() }}</div>{% endmacro %}),
    })
    env.from_string(%({% import "forms.html" as forms %}{% call forms.box("T") %}body{% endcall %})).render
      .should eq("<div>T:body</div>")
  end

  # Jinja2: "expected call". Without the check `{% call m %}` (parentheses
  # forgotten) dropped the body silently and `{% call v %}` printed `v`.
  it "rejects a call block whose expression is not a call" do
    ["{% macro m() %}{{ caller() }}{% endmacro %}{% call m %}body{% endcall %}",
     "{% set v = 1 %}{% call v %}body{% endcall %}",
     "{% macro m() %}{{ caller() }}{% endmacro %}{% call m() | upper %}body{% endcall %}"].each do |source|
      expect_raises(Crinja::TemplateSyntaxError, /expected call/) { render_call(source) }
    end
  end
end
