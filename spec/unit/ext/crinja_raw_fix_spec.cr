require "../../spec_helper"

private def render_raw(source : String) : String
  Crinja.new.from_string(source).render
end

# Expected strings are Jinja2 3.1's output for the same source.
describe "Crinja `{% raw %}`" do
  it "accepts a `{%- endraw %}` closer" do
    render_raw("{% raw %}\n  {{ a }}\n{%- endraw %}").should eq("\n  {{ a }}")
    render_raw("{%- raw -%} a {%- endraw -%}").should eq("a")
  end

  it "trims the raw content for `{% raw -%}`" do
    render_raw("{% raw -%}\n  {{ a }}\n{% endraw %}").should eq("{{ a }}\n")
    render_raw("[{% raw -%}   {%- endraw %}]").should eq("[]")
  end

  it "only closes on a complete `endraw` tag" do
    render_raw("{% raw %}x{% endrawx %}y{% endraw %}").should eq("x{% endrawx %}y")
    render_raw("{% raw %}{{ '{% endraw' }}{% endraw %}").should eq("{{ '{% endraw' }}")
  end

  it "still reports an unterminated raw block" do
    expect_raises(Crinja::TemplateSyntaxError) { render_raw("{% raw %}a{% endraw") }
  end
end
