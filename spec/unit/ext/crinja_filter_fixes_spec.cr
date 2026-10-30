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

  describe "wordcount" do
    it "counts word-character runs" do
      render_filter("{{ '' | wordcount }}|{{ ' -- ' | wordcount }}|{{ \"it's a-b\" | wordcount }}|{{ '한국어 문장 x_y 42' | wordcount }}")
        .should eq("0|0|4|4")
    end
  end

  describe "truncate" do
    it "keeps the text when the cut has no space" do
      render_filter("{{ 'abcdefghijklmnop' | truncate(10) }}").should eq("abcdefg...")
      render_filter("{{ '안녕하세요반갑습니다여러분안녕하세요반갑습니다' | truncate(10) }}").should eq("안녕하세요반갑...")
      render_filter("{{ 'abcdefghij' | truncate(5, leeway=0) }}").should eq("ab...")
    end

    it "returns a string within length + leeway whole" do
      render_filter("{{ 'Hello' | truncate(3) }}").should eq("Hello")
    end

    it "still cuts at the last space" do
      render_filter("{{ 'hello world foo bar' | truncate(12, leeway=0) }}").should eq("hello...")
      render_filter("{{ 'hello world foo bar' | truncate(12, true, leeway=0) }}").should eq("hello wor...")
    end
  end

  describe "format" do
    it "formats numbers with float conversions" do
      render_filter("{{ '%.2f' | format(3.14159) }}|{{ '%.1f' | format(4) }}|{{ '%5.1f%%' | format(12.345) }}|{{ '%03d' | format(7) }}|{{ '%s-%s' | format('a', 2) }}")
        .should eq("3.14|4.0| 12.3%|007|a-2")
    end
  end

  describe "float and int" do
    it "converts numbers and booleans" do
      render_filter("{{ 3 | float }}|{{ 1.5 | float }}|{{ true | float }}|{{ '2.5' | float }}|{{ 'x' | float }}")
        .should eq("3.0|1.5|1.0|2.5|0.0")
      render_filter("{{ true | int }}|{{ false | int }}|{{ 4.7 | int }}|{{ '42' | int }}|{{ 'x' | int(5) }}")
        .should eq("1|0|4|42|5")
    end
  end

  describe "min and max" do
    it "returns the smallest and largest item" do
      render_filter("{{ [3, 1, 2.5] | min }}|{{ [3, 1, 2.5] | max }}").should eq("1|3")
      render_filter("{{ ['b', 'A', 'c'] | min }}|{{ ['b', 'A', 'c'] | max }}").should eq("A|c")
    end

    it "compares strings case-insensitively unless case_sensitive=true" do
      render_filter("{{ ['b', 'a', 'C'] | max }}|{{ ['b', 'a', 'C'] | max(case_sensitive=true) }}").should eq("C|b")
      render_filter("{{ ['b', 'a', 'C'] | min(case_sensitive=true) }}").should eq("C")
      # Ties keep the first item, as in Python's min/max.
      render_filter("{{ ['a', 'A'] | min }}{{ ['A', 'a'] | max }}").should eq("aA")
    end

    it "compares by a (dotted) attribute and returns the whole item" do
      posts = Crinja.value([
        {"title" => "b", "extra" => {"weight" => 3}},
        {"title" => "A", "extra" => {"weight" => 1}},
        {"title" => "c", "extra" => {"weight" => 3}},
      ])
      Crinja.new.from_string("{{ (posts | max(attribute='extra.weight')).title }}|{{ (posts | min(attribute='title')).title }}")
        .render({"posts" => posts}).should eq("b|A")
    end

    it "iterates a mapping's keys, as Jinja2 does" do
      render_filter("{{ {'a': 1, 'z': 0, 'M': 5} | max }}|{{ {'a': 1, 'z': 0, 'M': 5} | min }}|{{ {} | max is undefined }}")
        .should eq("z|a|true")
    end

    it "gives undefined for an empty or undefined sequence" do
      render_filter("<{{ [] | max }}{{ [] | min }}{{ nope | max }}>|{{ ([] | max) is undefined }}").should eq("<>|true")
    end

    it "raises a template error for items that cannot be compared" do
      expect_raises(Crinja::TypeError) { render_filter("{{ [true, false] | max }}") }
      # NaN has no order: `<=>` returns nil, which must not escape as a bare
      # ArgumentError (that aborts the build without a template location).
      expect_raises(Crinja::TypeError) do
        Crinja.new.from_string("{{ xs | min }}").render({"xs" => Crinja.value([1.0, Float64::NAN])})
      end
    end
  end
end
