require "../../spec_helper"

private def render_filter(source : String) : String
  Crinja.new.from_string(source).render({"d" => Crinja.value({"b" => 2, "a" => 1, "C" => 3})})
end

# Expected strings are Jinja2 3.1's output for the same source.
describe "Crinja built-in filter fixes" do
  describe "dictsort" do
    it "honours reverse" do
      render_filter("{{ d | dictsort }}").should eq("[('a', 1), ('b', 2), ('C', 3)]")
      render_filter("{{ d | dictsort(reverse=true) }}").should eq("[('C', 3), ('b', 2), ('a', 1)]")
      render_filter("{{ d | dictsort(by='value', reverse=true) }}").should eq("[('C', 3), ('b', 2), ('a', 1)]")
      render_filter("{{ d | dictsort(true) }}").should eq("[('C', 3), ('a', 1), ('b', 2)]")
    end
  end
end
