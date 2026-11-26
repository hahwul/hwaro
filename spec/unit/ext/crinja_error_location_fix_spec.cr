require "../../spec_helper"

private def located_error(source : String) : Crinja::TemplateSyntaxError
  env = Hwaro::Content::Processors::TemplateEngine.new.env
  expect_raises(Crinja::TemplateSyntaxError) do
    Crinja::Template.new(source, env, "page.html", "page.html").render({} of String => Crinja::Value)
  end
end

# Both raised a plain Crystal exception outside any node (`Invalid Int64:
# "…"`, `Unexpected EOF`), so the build named neither the template nor the
# line.
describe "Crinja parse errors without a location" do
  it "locates an integer literal past Int64" do
    err = located_error("a\n{{ 99999999999999999999 }}")
    err.message.not_nil!.should contain("integer literal 99999999999999999999 is out of range")
    err.location_start.not_nil!.line.should eq(2)
    located_error("{{ [1, 2][1:99999999999999999999] }}").location_start.not_nil!.column.should eq(13)
  end

  it "locates a tag whose arguments end early" do
    {"{% for %}{% endfor %}", "{% for x, %}{% endfor %}", "{% macro %}{% endmacro %}",
     "{% filter %}x{% endfilter %}", "{% block %}{% endblock %}"}.each do |source|
      err = located_error("a\n#{source}")
      err.message.not_nil!.should contain("Unexpected end of tag")
      err.location_start.not_nil!.line.should eq(2)
    end
  end

  it "keeps literals in range working" do
    env = Hwaro::Content::Processors::TemplateEngine.new.env
    env.from_string("{{ 9223372036854775807 }}|{{ -9223372036854775807 }}").render.should eq("9223372036854775807|-9223372036854775807")
  end
end
