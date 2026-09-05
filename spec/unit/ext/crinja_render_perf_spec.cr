require "../../spec_helper"

# Guards for src/ext/crinja_render_perf.cr — the byte-compat render-path
# patches to the vendored Crinja runtime. These pin the semantics the
# patches must preserve: what may and may not be fragment-cached, that
# cached output is served only for the identical collection object, and
# that iteration-scope reuse cannot leak state between iterations or
# renders.
describe "ext/crinja_render_perf" do
  describe "for-loop fragment cache" do
    it "returns identical output when the same loop re-renders over the same collection object" do
      env = Crinja.new
      pages = Crinja::Value.new([
        Crinja::Value.new({"title" => Crinja::Value.new("A")}),
        Crinja::Value.new({"title" => Crinja::Value.new("B")}),
      ] of Crinja::Value)
      template = env.from_string("{% for p in items %}[{{ p.title }}:{{ loop.index }}/{{ loop.length }}]{% endfor %}")

      first = template.render({"items" => pages})
      second = template.render({"items" => pages})

      first.should eq("[A:1/2][B:2/2]")
      second.should eq(first)
      # The second render must have come from the cache (entry present).
      env.__for_fragment_cache.size.should eq(1)
    end

    it "does not serve a cached fragment for a different collection object" do
      env = Crinja.new
      template = env.from_string("{% for x in items %}{{ x }};{% endfor %}")
      a = Crinja::Value.new([Crinja::Value.new(1), Crinja::Value.new(2)] of Crinja::Value)
      b = Crinja::Value.new([Crinja::Value.new(9)] of Crinja::Value)

      template.render({"items" => a}).should eq("1;2;")
      template.render({"items" => b}).should eq("9;")
      template.render({"items" => a}).should eq("1;2;")
    end

    it "does not cache a body that reads variables outside the loop bindings" do
      env = Crinja.new
      items = Crinja::Value.new([Crinja::Value.new(1), Crinja::Value.new(2)] of Crinja::Value)
      template = env.from_string("{% for x in items %}{{ outer }}{{ x }}{% endfor %}")

      template.render({"items" => items, "outer" => "p1-"}).should eq("p1-1p1-2")
      # A stale cache would replay p1- here.
      template.render({"items" => items, "outer" => "p2-"}).should eq("p2-1p2-2")
      env.__for_fragment_cache.size.should eq(0)
    end

    it "does not cache bodies with nested tags, filters, or calls" do
      env = Crinja.new
      items = Crinja::Value.new([Crinja::Value.new("a")] of Crinja::Value)
      {
        "{% for x in items %}{% if x %}{{ x }}{% endif %}{% endfor %}",
        "{% for x in items %}{{ x | upper }}{% endfor %}",
        "{% for x in items %}{{ range(2) }}{% endfor %}",
      }.each do |source|
        template = env.from_string(source)
        template.render({"items" => items})
        env.__for_fragment_cache.size.should eq(0)
      end
    end

    it "caches a loop with an if condition over the loop variable" do
      env = Crinja.new
      items = Crinja::Value.new([Crinja::Value.new(1), Crinja::Value.new(0), Crinja::Value.new(2)] of Crinja::Value)
      template = env.from_string("{% for x in items if x %}{{ x }}{% endfor %}")

      template.render({"items" => items}).should eq("12")
      template.render({"items" => items}).should eq("12")
      env.__for_fragment_cache.size.should eq(1)
    end

    it "renders and caches the empty-collection path" do
      env = Crinja.new
      empty = Crinja::Value.new([] of Crinja::Value)
      template = env.from_string("<{% for x in items %}{{ x }}{% endfor %}>")

      template.render({"items" => empty}).should eq("<>")
      template.render({"items" => empty}).should eq("<>")
    end

    it "keeps else branches on the uncached path" do
      env = Crinja.new
      empty = Crinja::Value.new([] of Crinja::Value)
      template = env.from_string("{% for x in items %}{{ x }}{% else %}none{% endfor %}")

      template.render({"items" => empty}).should eq("none")
      env.__for_fragment_cache.size.should eq(0)
    end

    it "stops inserting past the cache cap but keeps rendering correctly" do
      env = Crinja.new
      template = env.from_string("{% for x in items %}{{ x }}{% endfor %}")
      (Crinja::Tag::For::FRAGMENT_CACHE_MAX + 5).times do |i|
        items = Crinja::Value.new([Crinja::Value.new(i)] of Crinja::Value)
        template.render({"items" => items}).should eq(i.to_s)
      end
      env.__for_fragment_cache.size.should eq(Crinja::Tag::For::FRAGMENT_CACHE_MAX)
    end
  end

  describe "iteration scope reuse" do
    it "does not leak item variables into the outer scope" do
      env = Crinja.new
      items = Crinja::Value.new([Crinja::Value.new("v")] of Crinja::Value)
      template = env.from_string("{% for x in items %}{{ x }}{% endfor %}|{{ x }}")

      template.render({"items" => items}).should eq("v|")
    end

    it "tracks loop metadata correctly across reused iterations" do
      env = Crinja.new
      items = Crinja::Value.new([Crinja::Value.new("a"), Crinja::Value.new("b"), Crinja::Value.new("c")] of Crinja::Value)
      template = env.from_string(
        "{% for x in items %}{{ loop.index }}{{ loop.first }}{{ loop.last }}:{% endfor %}")

      template.render({"items" => items}).should eq("1truefalse:2falsefalse:3falsetrue:")
    end

    it "unpacks multiple item variables per iteration" do
      env = Crinja.new
      pairs = Crinja::Value.new([
        Crinja::Value.new([Crinja::Value.new("k1"), Crinja::Value.new(1)] of Crinja::Value),
        Crinja::Value.new([Crinja::Value.new("k2"), Crinja::Value.new(2)] of Crinja::Value),
      ] of Crinja::Value)
      template = env.from_string("{% for k, v in pairs %}{{ k }}={{ v }};{% endfor %}")

      template.render({"pairs" => pairs}).should eq("k1=1;k2=2;")
    end
  end

  describe "scoped blocks inside loops (must stay uncached and capture per-iteration scope)" do
    it "renders scoped blocks with each iteration's variables" do
      env = Crinja.new
      loader = Crinja::Loader::HashLoader.new({
        "base.html"  => "{% for x in items %}{% block item scoped %}[{{ x }}]{% endblock %}{% endfor %}",
        "child.html" => "{% extends \"base.html\" %}{% block item %}<{{ x }}>{% endblock %}",
      })
      env.loader = loader

      env.get_template("child.html").render({"items" => Crinja::Value.new([
        Crinja::Value.new("a"), Crinja::Value.new("b"),
      ] of Crinja::Value)}).should eq("<a><b>")
      env.__for_fragment_cache.size.should eq(0)
    end
  end
end
