require "../../spec_helper"

private def render_slice(source : String, bindings = {} of String => Crinja::Value) : String
  vars = {
    "xs" => Crinja::Value.new((1..5).map { |i| Crinja::Value.new(i) }),
    "s"  => Crinja::Value.new("abcdef"),
  }
  vars.merge!(bindings)
  Crinja.new.from_string(source).render(vars)
end

# Expected strings are Jinja2 3.1's output for the same source.
describe "ext/crinja_slice_subscript" do
  it "slices lists with Python semantics" do
    {
      "{{ xs[:2] }}"          => "[1, 2]",
      "{{ xs[2:] }}"          => "[3, 4, 5]",
      "{{ xs[1:3] }}"         => "[2, 3]",
      "{{ xs[-2:] }}"         => "[4, 5]",
      "{{ xs[:-1] }}"         => "[1, 2, 3, 4]",
      "{{ xs[::2] }}"         => "[1, 3, 5]",
      "{{ xs[::-1] }}"        => "[5, 4, 3, 2, 1]",
      "{{ xs[3:1:-1] }}"      => "[4, 3]",
      "{{ xs[-1::-2] }}"      => "[5, 3, 1]",
      "{{ xs[10:] }}"         => "[]",
      "{{ xs[4:1] }}"         => "[]",
      "{{ xs[:100] }}"        => "[1, 2, 3, 4, 5]",
      "{{ xs[-100:2] }}"      => "[1, 2]",
      "{{ xs[none:2] }}"      => "[1, 2]",
      "{{ xs[:] }}"           => "[1, 2, 3, 4, 5]",
      "{{ xs[1:][0] }}"       => "2",
      "{{ xs[:2] | length }}" => "2",
    }.each do |source, expected|
      render_slice(source).should eq(expected), "#{source}"
    end
  end

  it "does not overflow on a huge step" do
    render_slice("{{ xs[1::9223372036854775807] }}").should eq("[2]")
    render_slice("{{ xs[3::-9223372036854775807] }}").should eq("[4]")
  end

  it "evaluates bounds as expressions" do
    render_slice("{{ xs[n:n+2] }}", {"n" => Crinja::Value.new(1)}).should eq("[2, 3]")
  end

  it "slices strings by character" do
    render_slice("{{ s[1:4] }}").should eq("bcd")
    render_slice("{{ s[::-1] }}").should eq("fedcba")
    render_slice("{{ s[:2] }}", {"s" => Crinja::Value.new("한글abc")}).should eq("한글")
  end

  it "keeps plain subscripts and for-loop filters working" do
    render_slice("{{ xs[1] }}").should eq("2")
    render_slice("{% for x in xs[:3] if x > 1 %}{{ x }}{% endfor %}").should eq("23")
  end

  it "raises on a zero step, a non-integer bound and a non-sequence" do
    expect_raises(Crinja::TypeError, /zero/) { render_slice("{{ xs[::0] }}") }
    expect_raises(Crinja::TypeError, /integers/) { render_slice("{{ xs[1.5:] }}") }
    expect_raises(Crinja::TypeError, /cannot be sliced/) do
      render_slice("{{ d[1:] }}", {"d" => Crinja::Value.new({"a" => Crinja::Value.new(1)})})
    end
  end

  it "lets a loop over a slice of the same list hit the fragment cache" do
    env = Crinja.new
    xs = Crinja::Value.new((1..20).map { |i| Crinja::Value.new(i) })
    template = env.from_string("{% for x in xs[:3] %}{{ x }};{% endfor %}")

    3.times { template.render({"xs" => xs}).should eq("1;2;3;") }
    env.__for_fragment_cache.size.should eq(1)
    # A different list is a different slice.
    template.render({"xs" => Crinja::Value.new([Crinja::Value.new(9)] of Crinja::Value)}).should eq("9;")
  end

  it "fragment-caches a loop over a slice of the loop-invariant list" do
    env = Crinja.new
    template = env.from_string("{% for x in xs %}{{ x[:1] }}{% endfor %}")
    template.render({"xs" => Crinja::Value.new([Crinja::Value.new("ab")] of Crinja::Value)})
    env.__for_fragment_cache.size.should eq(1)
  end
end
