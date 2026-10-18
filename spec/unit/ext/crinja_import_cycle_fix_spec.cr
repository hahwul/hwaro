require "../../spec_helper"

private def render_import(name : String) : String
  env = Crinja.new
  env.loader = Crinja::Loader::HashLoader.new({
    "macros.html" => %({% macro hi() %}hi{% endmacro %}),
    "base.html"   => %({% import "macros.html" as m %}<b>{{ m.hi() }}</b>{% block body %}{% endblock %}),
    "child.html"  => %({% extends "base.html" %}{% import "macros.html" as m %}{% block body %}<i>{{ m.hi() }}</i>{% endblock %}),
    "twice.html"  => %({% import "macros.html" as a %}{% import "macros.html" as b %}{{ a.hi() }}{{ b.hi() }}),
    "loop_a.html" => %({% import "loop_b.html" as b %}),
    "loop_b.html" => %({% import "loop_a.html" as a %}),
  })
  env.get_template(name).render
end

# Expected strings are Jinja2 3.1's output for the same templates.
describe "Crinja import cycle detection" do
  it "allows importing the same file twice in one render" do
    render_import("child.html").should eq("<b>hi</b><i>hi</i>")
    render_import("twice.html").should eq("hihi")
  end

  it "still reports a real import cycle" do
    expect_raises(Crinja::Error, /cycle/) { render_import("loop_a.html") }
  end
end
