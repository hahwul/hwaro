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

  describe "urlencode" do
    it "keeps slashes in a string, like Python's quote" do
      render_filter("{{ '/a b/c?d=é~*' | urlencode }}").should eq("/a%20b/c%3Fd%3D%C3%A9~%2A")
    end

    it "encodes a mapping as a query string" do
      render_filter("{{ {'a': 'b c', 'x': '/~*'} | urlencode }}").should eq("a=b+c&x=%2F~%2A")
    end
  end

  describe "indent" do
    it "leaves blank lines and the trailing newline unindented" do
      render_filter("{{ 'a\\n\\nb\\n' | indent(2) }}").should eq("a\n\n  b\n")
      render_filter("{{ 'a\\n  \\nb' | indent(2, blank=true) }}").should eq("a\n    \n  b")
    end

    it "supports first= and a string width" do
      render_filter("{{ 'a\\nb' | indent(width=3, first=true) }}").should eq("   a\n   b")
      render_filter("{{ 'a\\nb' | indent('> ') }}").should eq("a\n> b")
      render_filter("{{ 'a\\nb' | indent(2, true) }}").should eq("  a\n  b")
    end
  end
end
