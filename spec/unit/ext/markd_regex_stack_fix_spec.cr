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
    title_alphabet = ["\\", ")", "(", "\"", "'", "a", " ", "\\)", "\\\"", "\\'", "\\\\", "\u0000", "\n", "é"]

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
      tag_alphabet = ["<", ">", "/", "a", "b", "=", "\"", "'", " ", "-", "!", "--", "x=", "=\"v\"", "='v'", "=v", "\n", "`"]
      random_strings(11, tag_alphabet).each do |body|
        ["<a#{body}", "<!--#{body}", "</a#{body}", "<#{body}"].each do |text|
          ours = Fix::HTML_TAG.match_at_byte_index(text, 0).try(&.[0].bytesize)
          ours.should eq(upstream_length(Markd::Rule::HTML_TAG, text)), "tag #{text.inspect}"
        end
      end
    end

    it "matches the type-7 HTML block opener exactly like upstream" do
      block_alphabet = ["<", ">", "/", "a", "=", "\"", " ", "x=", "=\"v\"", "=v", "\t", "-"]
      random_strings(13, block_alphabet).each do |body|
        ["<a#{body}", "</a#{body}"].each do |text|
          ours = !!text.match(Fix::HTML_BLOCK_OPEN.last)
          ours.should eq(!!text.match(Markd::Rule::HTML_BLOCK_OPEN.last)), "block #{text.inspect}"
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

    it "renders a long run of unclosed links in linear-ish time" do
      render_within("[a](" * 16000 + "\n", 10.0).should start_with("<p>")
    end
  end
end
