require "../../spec_helper"

# ext/markd_regex_stack_fix.cr — markd regexes that repeat a group over a
# whole line raised `JIT stack limit reached` on long input, and
# `Inline#match` copied the rest of the paragraph on every call.

private alias Fix = Hwaro::MarkdRegexStackFix

# Deterministic random strings over the characters that steer each pattern.
private def random_strings(seed : Int32, alphabet : Array(String), count = 4000, max = 14) : Array(String)
  rng = Random.new(seed)
  Array.new(count) { String.build { |io| rng.rand(max + 1).times { io << alphabet.sample(rng) } } }
end

private def upstream_length(regex : Regex, text : String) : Int32?
  text.match(regex).try(&.[0].bytesize)
end

private def render_within(markdown : String, seconds : Float64) : String
  started = Time.instant
  html = Markd.to_html(markdown)
  (Time.instant - started).total_seconds.should be < seconds
  html
end

describe Hwaro::MarkdRegexStackFix do
  describe "equivalence with the upstream regexes (short input)" do
    title_alphabet = ["\\", ")", "(", "\"", "'", "a", " ", "\\)", "\\\"", "\\'", "\\\\", "\u0000", "\n", "é", "\u00A0", "\u3000", "\u2003", "\u202F", "\u0085", "\u2028", "\u1680", "\u205F"]

    it "scans link titles exactly like Rule::LINK_TITLE" do
      {'"' => '"', '\'' => '\'', '(' => ')'}.each do |open, close|
        random_strings(open.ord, title_alphabet).each do |body|
          text = "#{open}#{body}"
          expected = upstream_length(Markd::Rule::LINK_TITLE, text)
          Fix.bracketed_length(text, 0, close.ord.to_u8, {0_u8}).should eq(expected), "title #{text.inspect}"
        end
      end
    end

    it "scans link labels exactly like Rule::LINK_LABEL" do
      label_alphabet = ["\\", "[", "]", "a", " ", "\\]", "\\[", "\\\\", "\\a", "\u0000", "\n", "é"]
      random_strings(7, label_alphabet).each do |body|
        text = "[#{body}"
        expected = upstream_length(Markd::Rule::LINK_LABEL, text)
        Fix.bracketed_length(text, 0, ']'.ord.to_u8, {'['.ord.to_u8}).should eq(expected), "label #{text.inspect}"
      end
    end

    it "matches HTML tags exactly like Rule::HTML_TAG" do
      tag_alphabet = ["<", ">", "/", "a", "b", "=", "\"", "'", " ", "-", "!", "--", "x=", "=\"v\"", "='v'", "=v", "\n", "`", "\u00A0", "\u3000", "\u2003", "\u202F", "\u0085", "\u2028", "\u1680", "\u205F"]
      random_strings(11, tag_alphabet).each do |body|
        ["<a#{body}", "<!--#{body}", "</a#{body}", "<#{body}"].each do |text|
          Fix.html_tag_length(text, 0).should eq(upstream_length(Markd::Rule::HTML_TAG, text)), "tag #{text.inspect}"
        end
      end
    end

    it "matches the type-7 HTML block opener exactly like upstream" do
      block_alphabet = ["<", ">", "/", "a", "=", "\"", " ", "x=", "=\"v\"", "=v", "\t", "-", "\u00A0", "\u3000", "\u2003", "\u202F", "\u0085", "\u2028", "\u1680", "\u205F"]
      random_strings(13, block_alphabet).each do |body|
        ["<a#{body}", "</a#{body}"].each do |text|
          Fix.html_block_open?(text).should eq(!!text.match(Markd::Rule::HTML_BLOCK_OPEN.last)), "block #{text.inspect}"
        end
      end
    end

    it "matches braced destinations exactly like Rule::LINK_DESTINATION_BRACES" do
      dest_alphabet = ["<", ">", "\\", "\\>", "\\<", "\\a", "a", " ", "\t", "\n", "\u0000"]
      random_strings(17, dest_alphabet).each do |body|
        text = "<#{body}"
        ours = Fix::LINK_DESTINATION_BRACES.match_at_byte_index(text, 0).try(&.[0].bytesize)
        ours.should eq(upstream_length(Markd::Rule::LINK_DESTINATION_BRACES, text)), "dest #{text.inspect}"
      end
    end

    # PCRE2 runs markd's regexes with UCP, so `\s` also matches U+00A0,
    # U+3000, U+2000–U+200A, … — characters an unquoted attribute value may
    # also contain. Upstream backtracks the value to end before one so it can
    # start the next attribute; a possessive loop alone cannot.
    it "keeps upstream's reading of attributes separated by Unicode spaces" do
      ["<span title=a\u00A0class=b>", "<a b=x\u3000c='>'>", "<img src=a.png\u3000alt=x>", "<a href=/p\u2003title=\"t\">"].each do |tag|
        Fix.html_tag_length(tag, 0).should eq(upstream_length(Markd::Rule::HTML_TAG, tag))
        Fix.html_block_open?(tag).should eq(!!tag.match(Markd::Rule::HTML_BLOCK_OPEN.last))
      end
      Markd.to_html("x <span title=a\u00A0class=b>y</span>\n").should contain("<span title=a\u00A0class=b>")
      Markd.to_html("<img src=a.png\u3000alt=x>\n").should eq("<img src=a.png\u3000alt=x>\n")
    end

    it "matches email autolinks exactly like Rule::EMAIL_AUTO_LINK" do
      email_alphabet = ["a", "b", "1", "-", ".", "@", ">", "_", "+", "<", " "]
      random_strings(19, email_alphabet).each do |body|
        text = "<#{body}"
        ours = Fix::EMAIL_AUTO_LINK.match_at_byte_index(text, 0).try(&.[0].bytesize)
        ours.should eq(upstream_length(Markd::Rule::EMAIL_AUTO_LINK, text)), "email #{text.inspect}"
      end
    end

    # `Paragraph#token` now reads each definition at an offset into one
    # string instead of from a fresh slice; the two must agree exactly.
    it "reads reference definitions at an offset exactly as from a slice" do
      pieces = ["[a]: /u \"t\"\n", "[b]:\n/v\n", "[c]: <x y> (p)\n", "[d]: /w 't'\n", "[e]: /z \"bad\" x\n",
                "[f]:\n", "[ ]: /q\n", "[g]: /r\n\"multi\nline\"\n", "[h]: <>\n", "not a def\n", "[i]:/s\n",
                "[A]: /dup\n", "[j]: /t (un\\)closed\n", "[k\\]]: /e\n", "[l]: /é \"\u00A0\"\n"]
      rng = Random.new(23)
      300.times do
        text = String.build { |io| rng.rand(1..8).times { io << pieces.sample(rng) } }
        sliced = Markd::Parser::Inline.new(Markd::Options.new)
        offset_lexer = Markd::Parser::Inline.new(Markd::Options.new)
        sliced_map = {} of String => Hash(String, String)
        offset_map = {} of String => Hash(String, String)
        rest = text
        offset = 0
        loop do
          a = rest.starts_with?('[') ? sliced.reference(rest, sliced_map) : 0
          b = text.byte_at?(offset) == '['.ord ? offset_lexer.hwaro_reference_at(text, offset, offset_map) : 0
          b.should eq(a), "at #{offset} of #{text.inspect}"
          break if a <= 0
          rest = rest.byte_slice(a)
          offset += a
        end
        offset_map.should eq(sliced_map)
      end
    end

    it "renders a paragraph of reference definitions with the links they define" do
      Markd.to_html("[a]: /u \"t\"\n[b]: /v\n\n[a] [b]\n").should eq(
        "<p><a href=\"/u\" title=\"t\">a</a> <a href=\"/v\">b</a></p>\n")
    end

    it "renders ordinary links, titles, labels and inline HTML as before" do
      markdown = "[a](/u \"t\") [b](/v 'x') [c](/w (y)) [d](<p q> \"\\\"z\\\"\") " \
                 "<span class=\"k\" id=x>s</span> <!-- c --> [e]\n\n[e]: /r (ti\\)tle)\n"
      Markd.to_html(markdown).should eq(
        "<p><a href=\"/u\" title=\"t\">a</a> <a href=\"/v\" title=\"x\">b</a> " \
        "<a href=\"/w\" title=\"y\">c</a> <a href=\"p%20q\" title=\"&quot;z&quot;\">d</a> " \
        "<span class=\"k\" id=x>s</span> <!-- c --> <a href=\"/r\" title=\"ti)tle\">e</a></p>\n")
    end
  end

  describe "pathological lines" do
    it "renders an unclosed link title run without a JIT stack error" do
      render_within("[a](b (" * 7000 + "\n", 10.0).should start_with("<p>")
      render_within("[a](b \"" + "c " * 60000 + "\n", 10.0).should start_with("<p>")
      render_within("[a]: /u (" + "b (" * 30000 + "\n\n[a]\n", 10.0).should contain("[a]")
    end

    it "renders an HTML tag with 50k attributes, inline and as a block" do
      attrs = (0...50000).join(" ") { |i| %(a#{i}="x") }
      render_within("x <span #{attrs}> y\n", 10.0).should contain(%(a49999="x"))
      render_within("<x-foo #{attrs}>\n\nhi\n", 10.0).should contain("<x-foo")
    end

    it "renders a very long comment, label and braced destination" do
      render_within("x <!-- #{"ab " * 60000} --> y\n", 10.0).should contain("<!--")
      render_within("[#{"ab " * 60000}]\n", 10.0).should start_with("<p>")
      render_within("[a](<#{"b" * 200000}>)\n", 10.0).should contain("href=")
    end

    # Scaling, not a wall-clock constant: time a 4x larger input against a
    # smaller one (best of three, to damp scheduler noise on a busy CI box)
    # and require near-linear growth. Linear work grows ~4x, the quadratic
    # behaviour this guards against ~16x; 9 leaves room for a slow debug
    # build without letting that through.
    it "renders runs of unclosed links and titles in linear time" do
      best = ->(markdown : String) { Array.new(3) { started = Time.instant; Markd.to_html(markdown); Time.instant - started }.min }
      ["[a](", "[a](b ("].each do |unit|
        Markd.to_html(unit * 500 + "\n") # warm up
        small = best.call(unit * 6000 + "\n")
        large = best.call(unit * 24000 + "\n")
        ratio = large / {small, 1.millisecond}.max
        ratio.should be < 9.0, "#{unit.inspect}: #{small.total_milliseconds.round}ms -> #{large.total_milliseconds.round}ms"
      end
    end

    # A paragraph of consecutive reference definitions: upstream re-sliced
    # the rest of the paragraph after each one (quadratic), and the patched
    # lexer rebuilt its per-paragraph caches for every slice.
    it "reads a paragraph of consecutive reference definitions in linear time" do
      defs = ->(count : Int32) { String.build { |io| count.times { |i| io << "[l" << i << "]: /u" << i << " \"t\"\n" } } }
      best = ->(markdown : String) { Array.new(3) { started = Time.instant; Markd.to_html(markdown); Time.instant - started }.min }
      Markd.to_html(defs.call(300)) # warm up
      small = best.call(defs.call(2000))
      large = best.call(defs.call(8000))
      ratio = large / {small, 1.millisecond}.max
      ratio.should be < 9.0, "#{small.total_milliseconds.round}ms -> #{large.total_milliseconds.round}ms"
    end

    it "renders a very long email-like autolink without a JIT stack error" do
      render_within("<a@" + "b." * 100000 + "c>\n", 10.0).should start_with("<p>")
    end
  end
end
