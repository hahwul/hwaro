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

  it "strips newlines before `{%-` and `{{-`" do
    render_ws("[a\n{%- if true %}b{% endif %}]").should eq("[ab]")
    render_ws("[x\n{{- 1 -}}\ny]").should eq("[x1y]")
    render_ws("a\t\n\t{{- 'x' -}}\t\n\tb").should eq("axb")
  end

  it "strips newlines after `-%}` and keeps the untouched side intact" do
    render_ws("[{% if true -%}\nb\n{%- endif %}]\nZ").should eq("[b]\nZ")
    render_ws("{% set x = 1 -%}\n\n\nv={{ x }}").should eq("v=1")
  end

  it "strips across several blank lines on both sides" do
    render_ws("a  \n  \n {%- if true -%} \n\n  b  \n {%- endif -%}\n\n c").should eq("abc")
  end

  it "applies to comments" do
    render_ws("a\n{#- c -#}\nb").should eq("ab")
    render_ws("a \n {# c -#}\n b").should eq("a \n b")
  end

  it "strips inside loop, macro and filter bodies" do
    render_ws("{% for i in [1,2,3] -%}\n  {{ i }}\n{%- endfor %}").should eq("123")
    render_ws("<ul>\n{%- for i in [1,2] %}\n  <li>{{ i }}</li>\n{%- endfor %}\n</ul>")
      .should eq("<ul>\n  <li>1</li>\n  <li>2</li>\n</ul>")
    render_ws("{% macro m() -%}\n  M\n{%- endmacro %}[{{ m() }}]").should eq("[M]")
    render_ws("{% filter upper -%}\n  hi\n{%- endfilter %}").should eq("HI")
  end

  it "leaves text next to delimiters without `-` alone" do
    render_ws("a\n {% if true %}\n b\n {% endif %}\n c").should eq("a\n \n b\n \n c")
  end
end
