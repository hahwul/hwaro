require "../../spec_helper"

private def render_comment(source : String) : String
  Crinja.new.from_string(source).render
end

# Expected strings are Jinja2 3.1's output for the same source.
describe "Crinja `{# … #}` comments" do
  it "ignores template code inside a comment" do
    render_comment("a{# {{ x }} #}b").should eq("ab")
    render_comment("a{# {% if %} #}b").should eq("ab")
    render_comment("x{#\n{% include \"y\" %}\n#}y").should eq("xy")
  end

  it "keeps whitespace control around a comment holding code" do
    render_comment("a {#- {{ x }} }} %} -#} b").should eq("ab")
  end

  it "ends at the first `#}`" do
    render_comment("a{# x } # #}b{# c #}").should eq("ab")
  end

  it "still reports an unterminated comment" do
    expect_raises(Crinja::TemplateSyntaxError) { render_comment("a{# {{ x }}") }
  end
end
