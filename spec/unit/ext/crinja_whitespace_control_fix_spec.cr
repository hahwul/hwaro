require "../../spec_helper"

private def render_ws(source : String) : String
  Crinja.new.from_string(source).render
end

# Expected strings are Jinja2 3.1's output for the same source.
describe "Crinja whitespace control (`-` delimiters)" do
  it "does not carry a `-` over to the next delimiter" do
    render_ws("{% for i in [1] %}x{%- endfor %} {{ 'y' }}").should eq("x y")
    render_ws("{% if true -%}{% endif %}  z").should eq("  z")
    render_ws("{% if false %}a{%- else %}b  {% endif %}|").should eq("b  |")
    render_ws("{% if true %}a{% else -%}b{% endif %}  |").should eq("a  |")
    render_ws("{% block b -%}{% endblock %}  x").should eq("  x")
    render_ws("{{ 1 -}}{% if true %}{% endif %}  x").should eq("1  x")
  end

  it "honours `-}}` whatever follows the print statement" do
    render_ws("{{ 1 -}}  x").should eq("1x")
    render_ws("{{ 1 -}}  {{ 2 }}").should eq("12")
    render_ws("{{ 1 }}  {{ 2 -}}  ").should eq("1  2")
  end
end
