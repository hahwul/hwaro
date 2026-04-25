require "../spec_helper"
require "../../src/ext/crinja_resolve_fix"

# Regression tests for the resolver monkey-patches in
# `src/ext/crinja_resolve_fix.cr`. Both behaviors here originate from
# real bug reports against the vendored Crinja runtime.
describe "Crinja resolver patches" do
  describe "attribute access on indexable values (issue #482)" do
    it "raises a Crinja::UndefinedError with template location instead of ArgumentError" do
      env = Crinja.new
      # Iterating a Hash with a single loop variable yields `Tuple(k, v)`
      # per iteration; before the patch `tuple.name` triggered
      # `String#to_i` (via the indexable fallback) and surfaced as
      # `ArgumentError("Invalid Int32: \"name\"")` with a Crystal-
      # internal stack trace and no template location.
      template = env.from_string(%({% for k in items %}<{{ k.name }}>{% endfor %}))
      items = {"alpha" => "x", "beta" => "y"}

      ex = expect_raises(Crinja::UndefinedError) do
        template.render({"items" => items})
      end
      msg = ex.message.not_nil!
      msg.should contain("k.name")
      msg.should contain("template:") # file:line:col formatting
      msg.should_not contain("Invalid Int32")
    end

    it "raises with template location when accessing an attribute on a String value" do
      env = Crinja.new
      template = env.from_string("{{ s.name }}")

      ex = expect_raises(Crinja::UndefinedError) do
        template.render({"s" => "abc"})
      end
      ex.message.not_nil!.should contain("s.name")
    end

    it "still resolves numeric attribute access on arrays" do
      env = Crinja.new
      template = env.from_string("{{ a.0 }}")
      template.render({"a" => [10, 20, 30]}).should eq("10")
    end

    it "renders an undefined attribute on a hash silently (default Undefined behavior)" do
      env = Crinja.new
      template = env.from_string("[{{ h.missing }}]")
      template.render({"h" => {"x" => 1}}).should eq("[]")
    end
  end

  describe "empty-collection truthiness (issue #486)" do
    # Jinja2 treats empty collections as falsy so `{% if items %}` is
    # the canonical guard for "render this block only if there's
    # something to show". Crinja's default `truthy?` only saw `false`,
    # `0`, `nil`, and `Undefined` as falsy — empty `[]` / `{}` / `""`
    # rendered the block anyway, breaking the canonical lang-switcher
    # idiom from `docs/templates/data-model.md`.
    it "treats empty Array as falsy" do
      env = Crinja.new
      tpl = env.from_string("{% if items %}YES{% else %}NO{% endif %}")
      tpl.render({"items" => [] of Crinja::Value}).should eq("NO")
    end

    it "treats non-empty Array as truthy" do
      env = Crinja.new
      tpl = env.from_string("{% if items %}YES{% else %}NO{% endif %}")
      tpl.render({"items" => [Crinja::Value.new("x")]}).should eq("YES")
    end

    it "treats empty Hash as falsy" do
      env = Crinja.new
      tpl = env.from_string("{% if h %}YES{% else %}NO{% endif %}")
      tpl.render({"h" => {} of String => Crinja::Value}).should eq("NO")
    end

    it "treats empty String as falsy" do
      env = Crinja.new
      tpl = env.from_string("{% if s %}YES{% else %}NO{% endif %}")
      tpl.render({"s" => ""}).should eq("NO")
    end
  end

  describe "scope-vs-function priority (issue #224)" do
    it "prefers a context variable over a registered function with the same name" do
      env = Crinja.new
      env.functions["asset"] = Crinja.function { |_| Crinja::Value.new("function-result") }
      template = env.from_string(%({% for asset in items %}<{{ asset }}>{% endfor %}))
      template.render({"items" => ["a", "b"]}).should eq("<a><b>")
    end
  end
end
