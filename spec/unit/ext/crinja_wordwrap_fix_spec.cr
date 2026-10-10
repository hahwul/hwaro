require "../../spec_helper"

private def render_wrap(source : String) : String
  Crinja.new.from_string(source).render({"words" => Crinja::Value.new("the quick brown fox jumps over the lazy dog")})
end

# Expected strings are Jinja2 3.1's output for the same source.
describe "Crinja `wordwrap` filter" do
  it "breaks between words, not at a fixed column" do
    render_wrap("{{ words | wordwrap(7) }}").should eq("the\nquick\nbrown\nfox\njumps\nover\nthe\nlazy\ndog")
    render_wrap("{{ words | wordwrap(15, false, '|') }}").should eq("the quick brown|fox jumps over|the lazy dog")
    render_wrap("{{ '  lead  and   gaps   here  ' | wordwrap(6) }}").should eq("  lead\nand\ngaps\nhere")
  end

  it "splits a long word only when break_long_words is set" do
    render_wrap("{{ 'abcdefghijklmnop qr' | wordwrap(5) }}").should eq("abcde\nfghij\nklmno\np qr")
  end

  it "terminates on a long word with break_long_words=false" do
    render_wrap("{{ 'abcdefghijklmnop qr' | wordwrap(5, false) }}").should eq("abcdefghijklmnop\nqr")
  end

  it "rejects a width below 1 instead of hanging" do
    expect_raises(Crinja::Error, /width must be > 0/) { render_wrap("{{ 'x' | wordwrap(0) }}") }
  end
end
