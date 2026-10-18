require "../../spec_helper"

private def render_tag(source : String) : String
  Crinja.new.from_string(source).render
end

# Expected strings are Jinja2 3.1's output for the same source.
describe "Crinja nested dict literal inside a tag" do
  it "does not end the tag at a literal's closing braces" do
    render_tag(%({% set nav = {"home": {"url": "/"}} %}{{ nav.home.url }})).should eq("/")
    render_tag(%({% if {"a": {"b": 1}}.a.b %}y{% endif %})).should eq("y")
    render_tag(%({% for k in [{"a": {"b": 2}}] %}{{ k.a.b }}{% endfor %})).should eq("2")
    render_tag(%({% set x = {"a": {"b": 3} } %}{{ x.a.b }}|{% set y = {"a": 1} %}{{ y.a }})).should eq("3|1")
  end
end
