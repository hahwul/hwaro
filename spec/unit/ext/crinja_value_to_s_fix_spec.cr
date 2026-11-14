require "../../spec_helper"

private def render_to_s(source : String) : String
  Crinja.new.from_string(source).render
end

describe "Crinja::Value#to_s" do
  # Jinja2 3.1 renders the same strings.
  it "turns a list into the text `{{ list }}` prints" do
    render_to_s("{{ 'x' ~ [1, 'a'] }}").should eq("x[1, 'a']")
    render_to_s("{{ '%s' | format([1, 2]) }}").should eq("[1, 2]")
    render_to_s("{{ [1, 2] | center(8) }}").should eq(" [1, 2] ")
    render_to_s("{{ 'x' ~ [[1], []] }}").should eq("x[[1], []]")
  end

  it "turns a mapping into the text `{{ mapping }}` prints" do
    render_to_s("{{ 'x' ~ {'k': [1]} }}").should eq("x" + render_to_s("{{ {'k': [1]} }}"))
  end

  it "leaves scalars alone" do
    render_to_s("{{ 'a' ~ 1 ~ 1.5 ~ true ~ none }}").should eq("a11.5true")
  end
end
