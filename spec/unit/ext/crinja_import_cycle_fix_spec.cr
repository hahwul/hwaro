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

private def render_with_hwaro(name : String) : String
  env = Hwaro::Content::Processors::TemplateEngine.new.env
  env.loader = Crinja::Loader::HashLoader.new({
    "vars.html"   => %({% set color = "A B" | slugify %}{% set _hidden = 1 %}{% macro hi() %}hi{% endmacro %}),
    "as.html"     => %({% import "vars.html" as v %}[{{ v.color }}][{{ v._hidden }}][{{ v.hi() }}]),
    "from.html"   => %({% from "vars.html" import color, hi %}[{{ color }}][{{ hi() }}]),
    "plain.html"  => %({% import "macros.html" as m %}[{{ m is defined }}][{{ m.hi() }}]),
    "macros.html" => %({% macro hi() %}hi{% endmacro %}),
  })
  env.get_template(name).render
end

describe "Crinja imported file environment" do
  it "exposes an imported file's top-level variables on its `as` name" do
    render_with_hwaro("as.html").should eq("[a-b][][hi]")
  end

  it "runs a `from` import's top-level code with hwaro's filters" do
    render_with_hwaro("from.html").should eq("[a-b][hi]")
  end

  it "leaves the `as` name undefined when the file sets nothing" do
    render_with_hwaro("plain.html").should eq("[false][hi]")
  end
end
