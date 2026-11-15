require "../../spec_helper"

# `[templates] autoescape` at the engine level: which templates escape, and
# Jinja2's Markup rules for filters, operators and tags (src/ext/crinja_autoescape.cr
# plus the hwaro filters in content/processors/filters/).

private CANARY  = %(<b a="x">&')
private ESCAPED = "&lt;b a=&quot;x&quot;&gt;&amp;&#39;"

private def ae_render(source : String, autoescape : Bool = true, filename : String? = nil,
                      vars : Hash(String, Crinja::Value) = {} of String => Crinja::Value) : String
  env = Hwaro::Content::Processors::TemplateEngine.new(autoescape).env
  template = filename ? Crinja::Template.new(source, env, filename, filename) : env.from_string(source)
  template.render(vars)
end

# `u` is author text with every HTML-special character, `s` a safe value.
private def ae_vars : Hash(String, Crinja::Value)
  {
    "u" => Crinja::Value.new(CANARY),
    "s" => Crinja::Value.new(Crinja::SafeString.new("<i>s&amp;</i>")),
    "d" => Crinja::Value.new({"k" => Crinja::Value.new("<v>&'")}),
  } of String => Crinja::Value
end

private def on(source : String) : String
  ae_render(source, vars: ae_vars)
end

private def off(source : String) : String
  ae_render(source, autoescape: false, vars: ae_vars)
end

describe "Crinja autoescape" do
  describe "which templates escape" do
    it "escapes HTML/XML outputs and names without a type, not text outputs" do
      {
        "templates/page.html"           => true,
        "templates/page.j2"             => true,
        "templates/page.jinja2"         => true,
        "templates/page.ecr"            => true,
        "templates/page.xml.jinja"      => true,
        "templates/rss.xml"             => true,
        "templates/page.json.jinja"     => false,
        "templates/page.json.jinja2"    => false,
        "templates/page.txt.j2"         => false,
        "templates/page.csv.jinja"      => false,
        "templates/partials/app.js"     => false,
        "templates/partials/style.css"  => false,
        "templates/generate/product.md" => false,
      }.each do |name, escapes|
        ae_render("{{ u }}", filename: name, vars: ae_vars).should eq(escapes ? ESCAPED : CANARY), name
      end
    end

    it "escapes a template compiled from a string" do
      on("{{ u }}").should eq(ESCAPED)
    end

    it "never escapes with the switch off, whatever the name" do
      ae_render("{{ u }}", autoescape: false, filename: "templates/page.html", vars: ae_vars).should eq(CANARY)
      off("{{ u }}").should eq(CANARY)
    end

    it "lets a template opt out with __no_autoescape" do
      env = Hwaro::Content::Processors::TemplateEngine.new(true).env
      template = env.from_string("{{ u }}")
      template.__no_autoescape = true
      template.render(ae_vars).should eq(CANARY)
    end

    it "escapes exactly what HTML.escape does, wherever the character sits" do
      ["&", "<", ">", %("), "'"].each do |char|
        (0..19).each do |at|
          (at..at + 9).each do |size|
            s = ("x" * at) + char + ("y" * (size - at))
            Crinja::Markup.escape(s).should eq(HTML.escape(s))
          end
        end
      end
      clean = "plain-ascii/path_0123456789 UTF-8: 한국어 é 😀"
      Crinja::Markup.escape(clean).should be(clean)
      (0..17).each { |n| Crinja::Markup.escape("z" * n).should eq("z" * n) }
      (0..9).each { |n| Crinja::Markup.escape(("é" * n) + "<" + "😀").should eq(("é" * n) + "&lt;😀") }
    end

    it "prints a safe value, a number and a plain string with nothing to escape as is" do
      on("{{ s }}|{{ 5 }}|{{ 'plain' }}").should eq("<i>s&amp;</i>|5|plain")
    end
  end

  describe "{% autoescape %}" do
    it "turns escaping off and back on inside a template" do
      on("{% autoescape false %}{{ u }}{% endautoescape %}|{{ u }}").should eq("#{CANARY}|#{ESCAPED}")
      off("{% autoescape true %}{{ u }}{% endautoescape %}|{{ u }}").should eq("#{ESCAPED}|#{CANARY}")
    end

    it "keeps the fragment cache of a closed loop apart per mode" do
      on("{% autoescape false %}{% for i in [u] %}{{ i }}{% endfor %}{% endautoescape %}{% for i in [u] %}{{ i }}{% endfor %}")
        .should eq("#{CANARY}#{ESCAPED}")
    end

    it "escapes inside a macro, whose output is safe" do
      on(%({% macro m(a) %}<i>{{ a }}</i>{% endmacro %}{{ m(u) }}|{{ m(u) | e }})).should eq("<i>#{ESCAPED}</i>|<i>#{ESCAPED}</i>")
    end
  end

  describe "filters keep Jinja2's safety rules" do
    it "escape/e do not double-escape; forceescape does; safe marks" do
      on("{{ u | e }}|{{ s | e }}|{{ s | forceescape }}|{{ u | safe }}")
        .should eq("#{ESCAPED}|<i>s&amp;</i>|&lt;i&gt;s&amp;amp;&lt;/i&gt;|#{CANARY}")
    end

    it "keeps a safe value safe through string filters and escapes what they insert" do
      on("{{ s | upper }}").should eq("<I>S&AMP;</I>")
      on("{{ s | trim }}|{{ s | string }}|{{ s | default('x') }}").should eq("<i>s&amp;</i>|<i>s&amp;</i>|<i>s&amp;</i>")
      on(%({{ s | truncate(5, true, "<>", 0) }})).should eq("<i>&lt;&gt;")
      on(%({{ s | replace("i", u) }})).should eq("<#{ESCAPED}>s&amp;</#{ESCAPED}>")
      on(%({{ "a b c" | safe | truncate_words(1, end="<>") }})).should eq("a&lt;&gt;")
      on(%({{ s | regex_replace(pattern="i", rep="<u>") }})).should eq("<&lt;u&gt;>s&amp;</&lt;u&gt;>")
      on(%({{ "%s|%s" | safe | format(u, s) }})).should eq("#{ESCAPED}|<i>s&amp;</i>")
    end

    it "escapes the result of a string filter on plain text once" do
      on("{{ u | upper }}").should eq("&lt;B A=&quot;X&quot;&gt;&amp;&#39;")
      on("{{ u | string }}").should eq(ESCAPED)
      on("{{ u | truncate(3, true, '', 0) }}").should eq("&lt;b ")
    end

    it "joins with an escaped separator and escaped items" do
      on(%({{ ["a", u] | join("<br>") }})).should eq("a&lt;br&gt;#{ESCAPED}")
      on(%({{ [s, s] | join("<br>" | safe) }})).should eq("<i>s&amp;</i><br><i>s&amp;</i>")
    end

    it "urlize escapes the text it links" do
      on(%({{ ("see http://x.com/?a=1&b=2 " ~ u) | urlize }}))
        .should eq(%(see <a href="http://x.com/?a=1&amp;b=2" rel="noopener">http://x.com/?a=1&amp;b=2</a> #{ESCAPED}))
    end

    it "returns HTML from markdownify and an escaped value from xml_escape, both safe" do
      on(%({{ "**a** &amp;" | markdownify }})).should eq("<p><strong>a</strong> &amp;</p>\n")
      on("{{ u | xml_escape }}|{{ s | xml_escape }}").should eq("&lt;b a=&quot;x&quot;&gt;&amp;&apos;|&lt;i&gt;s&amp;amp;&lt;/i&gt;")
    end

    it "strip_html and striptags give text that is escaped exactly once" do
      on(%({{ "<p>a &amp; b &lt;c&gt;</p>" | safe | strip_html }}|{{ s | striptags }})).should eq("a &amp; b &lt;c&gt;|s&amp;")
    end

    it "tojson/jsonify are safe JSON a <script> cannot be broken out of" do
      on("{{ d | tojson }}|{{ u | jsonify }}")
        .should eq(%({"k":"\\u003cv\\u003e\\u0026\\u0027"}|"\\u003cb a=\\"x\\"\\u003e\\u0026\\u0027"))
    end

    it "returns plain text from text filters (escaped when printed)" do
      on("{{ u | slugify }}|{{ u | urlencode }}|{{ u | t }}").should eq("b-ax|%3Cb%20a%3D%22x%22%3E%26%27|#{ESCAPED}")
    end
  end

  describe "operators and tags" do
    it "concatenation with a safe operand escapes the other one" do
      on("{{ s ~ u }}|{{ u + s }}|{{ u ~ u }}").should eq("<i>s&amp;</i>#{ESCAPED}|#{ESCAPED}<i>s&amp;</i>|#{ESCAPED}#{ESCAPED}")
      on(%({{ "<p>" ~ s }})).should eq("&lt;p&gt;<i>s&amp;</i>")
    end

    it "a set block and a call block are safe markup of their escaped body" do
      on("{% set x %}<b>{{ u }}</b>{% endset %}{{ x }}|{{ x | e }}").should eq("<b>#{ESCAPED}</b>|<b>#{ESCAPED}</b>")
      on("{% macro w() %}[{{ caller() }}]{% endmacro %}{% call w() %}<em>{{ u }}</em>{% endcall %}").should eq("[<em>#{ESCAPED}</em>]")
    end

    it "a filter block hands its body over as markup and escapes a plain result" do
      on("{% filter upper %}<b>{{ s }}</b>{% endfilter %}").should eq("<B><I>S&AMP;</I></B>")
      on("{% filter striptags %}<b>{{ u }}</b>{% endfilter %}").should eq(ESCAPED)
    end
  end

  describe "with the switch off" do
    it "renders exactly as before" do
      off("{{ u }}|{{ u | e }}|{{ u | upper }}").should eq("#{CANARY}|#{ESCAPED}|<B A=\"X\">&'")
      off(%({{ ["a", u] | join("<br>") }})).should eq("a<br>#{CANARY}")
      off(%({{ d | tojson }})).should eq(%({"k":"<v>&'"}))
      off(%({{ "</x>" | tojson }})).should eq(%("<\\/x>"))
      off(%({{ "<p>a &amp; b</p>" | safe | strip_html }})).should eq("a &amp; b")
      off("{% filter striptags %}<b>{{ u }}</b>{% endfilter %}").should eq("&'")
      off("{{ u | string }}|{{ s ~ u }}").should eq("#{CANARY}|<i>s&amp;</i>#{CANARY}")
      off(%({{ ("http://x.com/?a=1&b=2 " ~ u) | urlize }})).should eq(%(<a href="http://x.com/?a=1&b=2" rel="noopener">http://x.com/?a=1&b=2</a> #{CANARY}))
    end
  end

  # Review-round regressions. Each asserts the Jinja2/markupsafe behaviour a
  # finding said the branch got wrong.
  describe "review fixes" do
    it "#3/#4 escapes every inserted filter argument, whatever its type" do
      on("{{ s | indent(width=u, indentfirst=true) }}").should eq("#{ESCAPED}<i>s&amp;</i>")
      on(%({% set f = "<b>%s</b>" | safe %}{{ f | format([u]) }}))
        .should eq("<b>[&#39;#{ESCAPED}&#39;]</b>")
      on(%({{ s | replace("i", d) }}))
        .should eq("<{&#39;k&#39; =&gt; &#39;&lt;v&gt;&amp;&#39;&#39;}>s&amp;</{&#39;k&#39; =&gt; &#39;&lt;v&gt;&amp;&#39;&#39;}>")
    end

    it "#9 replace keeps a safe replacement's markup and escapes the unsafe source" do
      on(%({{ "A&X" | replace("X", s) }})).should eq("A&amp;<i>s&amp;</i>")
      on(%({{ "A&X" | safe | replace("X", "<b>" | safe) }})).should eq("A&<b>")
    end

    it "#10 escapes a truncation suffix only when it is actually appended" do
      on(%({% set t %} <b>x</b> {% endset %}{{ t | truncate_words(50, end="</b>") }})).should eq("<b>x</b>")
      on(%({{ "<b>x</b> and more words now" | safe | truncate_words(3, end="</b>") }}))
        .should eq("<b>x</b> and more&lt;/b&gt;")
      on(%({{ "  <b>x</b>  " | safe | truncate(50, true, "</b>", 0) }})).should eq("  <b>x</b>  ")
    end

    it "#6 escapes a plain {% call %} result, keeps a macro's safe markup" do
      on("{% call env(name=\"__AE_MISSING__\", default=u) %}{% endcall %}").should eq(ESCAPED)
      # A macro's output is safe markup: its own tags pass through, and a
      # `{{ … }}` printed inside its body is escaped there, not again.
      on("{% macro w(a) %}<i>{{ a }}{{ caller() }}</i>{% endmacro %}{% call w(u) %}x{% endcall %}").should eq("<i>#{ESCAPED}x</i>")
    end

    it "#7 a capture made under autoescape false is plain outside it" do
      on("{% autoescape false %}{% set x %}{{ u }}{% endset %}{% endautoescape %}{{ x }}").should eq(ESCAPED)
      on("{% set x %}{{ u }}{% endset %}{{ x }}").should eq(ESCAPED) # captured under on → safe, prints once-escaped
    end

    it "#8 xmlattr rejects an attribute name with a space, slash, gt or eq" do
      {" " => "x y", "/" => "x/y", ">" => "x>y", "=" => "x=y"}.each do |_, key|
        expect_raises(Crinja::RuntimeError, /invalid attribute name/) do
          on(%({{ {#{key.inspect}: "v"} | xmlattr }}))
        end
      end
      on(%({{ {"data-x": "a&b"} | xmlattr }})).should eq(%( data-x="a&amp;b"))
    end

    it "#8/#9 does NOT validate with the switch off (OFF output unchanged)" do
      off(%({{ {"x y": "v"} | xmlattr }})).should eq(%( x y="v"))
    end

    it "#13 escape matches HTML.escape at every offset and never overflows" do
      ["&", "<", ">", %("), "'"].each do |char|
        (0..19).each do |at|
          (at..at + 10).each do |size|
            str = ("x" * at) + char + ("y" * (size - at))
            Crinja::Markup.escape(str).should eq(HTML.escape(str))
          end
        end
      end
      clean = "a" * 40
      Crinja::Markup.escape(clean).should be(clean) # no copy when nothing to escape
    end

    it "#12 gates the new semantics on the site switch, not the tag" do
      # With the switch OFF, an inner {% autoescape true %} reproduces the old
      # (pre-branch) engine byte-for-byte: string is double-escaped as before.
      off("{% autoescape true %}{{ u | string }}{% endautoescape %}").should eq("&amp;lt;b a=&amp;quot;x&amp;quot;&amp;gt;&amp;amp;&amp;#39;")
    end
  end

  # Review round 2 regressions.
  describe "review round 2" do
    it "r2#2 escapes the WHOLE representation of a non-string value once" do
      # The structural quotes/brackets are escaped too — ON == HTML.escape(OFF repr).
      ["{{ [u] }}", "{{ d }}", "{{ (u, u) }}"].each do |c|
        on(c).should eq(HTML.escape(off(c))), c
      end
      on("{{ [u] }}").should_not contain(%('])) # no raw closing structural quote
    end

    it "r2#2 escapes a printed callable's representation" do
      src = "{% macro w() %}[{{ caller }}]{% endmacro %}{% call(y=u) w() %}{% endcall %}"
      on(src).should contain("&#39;")
      on(src).should_not contain("<b a=")
    end

    it "r2#3 format with %c does not synthesize raw markup" do
      on("{% set f = \"%c%s%c\" | safe %}{{ f | format(60, u, 62) }}").should_not contain("<b a=")
      # legitimate numeric formatting is byte-identical to off
      ["%d", "%05d", "%x"].each do |conv|
        src = "{% set f = #{conv.inspect} | safe %}{{ f | format(255) }}"
        on(src).should eq(off(src)), conv
      end
    end

    it "r2#4 producers under {% autoescape false %} are plain, escaped where printed" do
      on("{% autoescape false %}{% set x = [u] | join %}{% endautoescape %}{{ x }}").should eq(ESCAPED)
      on("{% autoescape false %}{% set x = u | urlize %}{% endautoescape %}{{ x }}").should eq(ESCAPED)
      on("{% macro m(v) %}{{ v }}{% endmacro %}{% autoescape false %}{% set x = m(u) %}{% endautoescape %}{{ x }}").should eq(ESCAPED)
      # still safe in the normal escaping context
      on("{{ [s] | join }}").should eq("<i>s&amp;</i>")
    end

    it "r2#5 urlize does not link an unsafe scheme (both modes)" do
      js = "javascript://x/%0Aalert(1)"
      on(%({{ #{js.inspect} | urlize }})).should_not contain("<a ")
      off(%({{ #{js.inspect} | urlize }})).should_not contain("<a ")
      on(%({{ "http://example.com/" | urlize }})).should contain(%(<a href="http://example.com/"))
    end

    it "r2#6 replace does not escape the search, and counts matches in the source" do
      on(%({{ s | replace("<i>", "") }})).should eq("s&amp;</i>")
      on(%({% set a %}ab{% endset %}{{ a | replace("a", "aX", 2) }})).should eq("aXb")
      on(%({% set a %}ab{% endset %}{{ a | replace("a", "aX", -1) }})).should eq("aXb")
    end

    it "r2#7 a safe truncation suffix stays safe, with any target" do
      on(%({% set t %}<i/>{% endset %}{{ "abcdef" | truncate(5, true, t, 0) }})).should eq("a<i/>")
      on(%({% set t %}<i/>{% endset %}{{ "a b" | safe | truncate_words(1, end=t) }})).should eq("a<i/>")
      # a plain suffix is still escaped, and an untruncated safe string untouched
      on(%({{ "a b c" | safe | truncate_words(1, end="</b>") }})).should eq("a</b>".sub("</b>", "&lt;/b&gt;"))
    end

    it "r2#11 urlize coerces an Int64 trim_url_limit and a SafeString target" do
      on(%({{ "http://example.com/" | urlize(trim_url_limit=20) }})).should contain(%(<a href="http://example.com/"))
      on("{{ s | urlize(trim_url_limit=20) }}").should eq("<i>s&amp;</i>")
    end
  end

  # Review round 2b regressions.
  describe "review round 2b" do
    it "r2b#A format catches a %c conversion with a width, flags or a position" do
      vars = ae_vars.merge({"x" => Crinja::Value.new("img src=x onerror=alert(1)")})
      [%("%1c%s%1c"), %("%-1c%s%-1c"), %("%1$c%2$s%3$c"), %("% 01c%s%01c")].each do |fmt|
        out = ae_render(%({{ #{fmt} | safe | format(60, x, 62) }}), vars: vars)
        out.should_not contain("<img"), fmt
      end
      # A `%%` is a literal percent, not a conversion: the safe path holds.
      on(%({{ "<i>100%%certain %d</i>" | safe | format(1) }})).should eq("<i>100%certain 1</i>")
      ["%d", "%05d", "%.2f", "%x", "%%"].each do |conv|
        src = %({{ "<i>#{conv}</i>" | safe | format(255) }})
        on(src).should eq(off(src)), conv
      end
      # A named `%<a>c` needs a hash argument, which `format`'s varargs never are.
      expect_raises(Crinja::Error) { on(%({{ "%<a>c" | safe | format({"a": 60}) }})) }
    end

    it "r2b#B the URL filters leave a pre-escaped URL alone with the switch off" do
      pre = %("/a?x=1&amp;y=2" | safe)
      off("{{ #{pre} | absolute_url }}").should eq("/a?x=1&amp;y=2")
      off("{{ #{pre} | relative_url }}").should eq("/a?x=1&amp;y=2")
      off("{{ url_for(path=#{pre}) }}").should eq("/a?x=1&amp;y=2")
      off("{{ get_url(path=#{pre}) }}").should eq("/a?x=1&amp;y=2")
      on("{{ #{pre} | absolute_url }}").should eq("/a?x=1&amp;y=2")
    end

    it "r2b#C1 a printed non-string inside {% autoescape true %} is unchanged with the switch off" do
      off("{% autoescape true %}{{ [u] }}{% endautoescape %}").should eq("['#{ESCAPED}']")
      off("{% autoescape true %}{{ d }}{% endautoescape %}").should eq("{'k' => '&lt;v&gt;&amp;&#39;'}")
    end

    it "r2b#C2 every env.stringify caller escapes a container's whole representation" do
      inner = "['#{CANARY}']"
      on("{{ [[u]] | join }}").should eq(HTML.escape(inner))
      on("{{ [d] | join }}").should eq(HTML.escape("{'k' => '<v>&''}"))
      # the other ways a container reaches the output
      ["{{ [u] | string }}", "{{ [u] ~ '' }}", %({{ "%s" | safe | format([u]) }}),
       "{% filter upper %}{{ [u] }}{% endfilter %}", "{% set x %}{{ [u] }}{% endset %}{{ x }}",
       "{% for i in [1] %}{{ loop.cycle([u]) }}{% endfor %}", "{{ [u] + [u] }}"].each do |c|
        out = on(c)
        out.should_not contain("'"), c
        out.should_not contain("<"), c
      end
      # off, and off inside {% autoescape true %}: the finalizer's own bytes
      off("{{ [[u]] | join }}").should eq(inner)
      off("{% autoescape true %}{{ [[u]] | join }}{% endautoescape %}").should eq("['#{ESCAPED}']")
    end

    it "r3#1 a %c format escapes its plain arguments once, not twice" do
      on(%({{ ("%s%c" | safe) | format(u, 60) }})).should eq(ESCAPED + "&lt;")
      on(%({{ ("%s%c" | safe) | format(s, 62) }})).should eq(HTML.escape("<i>s&amp;</i>>"))
    end

    it "r3#2 the URL filters reverse only hwaro's own five encodings, once" do
      on(%({{ ("https://x.test/?a=1&copy=2" | safe) | relative_url }})).should eq("https://x.test/?a=1&amp;copy=2")
      on(%({{ ("/p?a=1&amp;copy=2" | safe) | absolute_url }})).should eq("/p?a=1&amp;copy=2")
      on(%({{ ("/p?a=1&amp;lt;" | safe) | relative_url }})).should eq("/p?a=1&amp;lt;")
      on(%({{ url_for(path=("/p?q=&quot;x&#39;&lt;&gt;" | safe)) }})).should eq("/p?q=&quot;x&#39;&lt;&gt;")
      on(%({{ ("/p?a=&eacute;&#x27;" | safe) | relative_url }})).should eq("/p?a=&amp;eacute;&amp;#x27;")
    end

    it "r2b#D replace with a count handles multi-byte text" do
      on(%({% set a %}가나가나가{% endset %}{{ a | replace("가", "<b>", 2) }})).should eq("&lt;b&gt;나&lt;b&gt;나가")
      on(%({% set a %}é<i>é</i>é{% endset %}{{ a | replace("é", "ü", 1) }})).should eq("ü<i>é</i>é")
      on(%({% set a %}가가{% endset %}{{ a | replace("가", "", 5) }})).should eq("")
    end
  end

  describe "text renders" do
    it "a text output's includes never escape; an HTML output's follow their own names" do
      Dir.mktmpdir do |dir|
        {"p.html" => "{{ u }}", "s.js" => "{{ u }}", "page.json" => %({"x": "{% include "p.html" %}"}),
         "page.html" => %(<{% include "p.html" %}|{% include "s.js" %}>)}.each do |name, source|
          File.write(File.join(dir, name), source)
        end
        env = Hwaro::Content::Processors::TemplateEngine.new(true).env
        env.loader = Crinja::Loader::FileSystemLoader.new(dir)
        env.get_template("page.json").render(ae_vars).should eq(%({"x": "#{CANARY}"}))
        env.get_template("page.html").render(ae_vars).should eq("<#{ESCAPED}|#{CANARY}>")
        env.get_template("p.html").render_text(ae_vars).should eq(CANARY)
        env.get_template("p.html").render(ae_vars).should eq(ESCAPED)
      end
    end
  end

  # Review round 4: no render state outlives its render.
  describe "render state" do
    files = {
      "empty.txt"    => "",
      "title.html"   => "{{ u }}",
      "page.html"    => %({% include "empty.txt" without context %}{% include "title.html" %}),
      "other.html"   => "{{ u }}",
      "bad.txt"      => %({{ u }}{% include "missing.html" %}),
      "literal.html" => %({{ "A&B" }}),
      "vars.html"    => %({% set label %}{{ "A&B" }}{% endset %}),
      "inc.txt"      => %({% include "literal.html" without context %}),
      "from.txt"     => %({% from "vars.html" import label %}{{ label }}),
    }
    with_env = ->(block : Crinja -> Nil) do
      Dir.mktmpdir do |dir|
        files.each { |name, source| File.write(File.join(dir, name), source) }
        env = Hwaro::Content::Processors::TemplateEngine.new(true).env
        env.loader = Crinja::Loader::FileSystemLoader.new(dir)
        block.call(env)
      end
    end

    it "r4#1 a text include without context does not switch escaping off for the rest" do
      with_env.call(->(env : Crinja) {
        env.get_template("page.html").render(ae_vars).should eq(ESCAPED)
        # a later page on the same environment
        env.get_template("other.html").render(ae_vars).should eq(ESCAPED)
        nil
      })
    end

    it "r4#1 a text render that raises leaves the environment escaping" do
      with_env.call(->(env : Crinja) {
        expect_raises(Crinja::Error) { env.get_template("bad.txt").render(ae_vars) }
        expect_raises(Crinja::Error) { env.get_template("bad.txt").render_text(ae_vars) }
        env.get_template("other.html").render(ae_vars).should eq(ESCAPED)
        nil
      })
    end

    it "r4#3 a text output's context-free include and import do not escape" do
      with_env.call(->(env : Crinja) {
        env.get_template("inc.txt").render(ae_vars).should eq("A&B")
        env.get_template("from.txt").render(ae_vars).should eq("A&B")
        env.get_template("literal.html").render(ae_vars).should eq("A&amp;B")
        nil
      })
    end

    it "r4#2 an entry template rendered for an HTML file escapes whatever its name" do
      with_env.call(->(env : Crinja) {
        env.get_template("title.html").render_entry(ae_vars, html: true).should eq(ESCAPED)
        env.from_string("{{ u }}").tap(&.__no_autoescape = true).render(ae_vars).should eq(CANARY)
        Crinja::Template.new("{{ u }}", env, "plain.txt", "plain.txt").render_entry(ae_vars, html: true).should eq(ESCAPED)
        Crinja::Template.new("{{ u }}", env, "page.html", "page.html").render_entry(ae_vars, html: false).should eq(CANARY)
        nil
      })
    end
  end

  # Review round 4: inside a text render the engine behaves as with the switch off.
  describe "text render semantics" do
    it "r4#4 captures, producers, URL and xmlattr behave exactly as with the switch off" do
      src = %({% set x %}A&B{% endset %}{{ x | e }}|{{ ["A&B"] | join | e }}|{% macro m() %}A&B{% endmacro %}{{ m() | e }}|) +
            %({{ "/x?a=1&amp;b=2" | safe | relative_url }}|{{ {"x y": "v"} | xmlattr }}|{{ [u] }}|{{ u ~ ("<s>" | safe) }}|{{ u | string }})
      on = Hwaro::Content::Processors::TemplateEngine.new(true).env.from_string(src).render_text(ae_vars)
      off = Hwaro::Content::Processors::TemplateEngine.new(false).env.from_string(src).render(ae_vars)
      on.should eq(off)
    end
  end

  # Review round 4: `| e` on HTML hwaro rendered still escapes it.
  describe "| e on rendered HTML" do
    it "r4#5 escapes hwaro's HTML values, leaves other safe values alone, in every mode" do
      [true, false].each do |ae|
        vars = {
          "content" => Hwaro::Utils::CrinjaUtils.html_value("<p>x &amp; y</p>", ae),
          "dest"    => Hwaro::Utils::CrinjaUtils.preescaped_value("/a?b=1&amp;c=2", ae),
        } of String => Crinja::Value
        env = Hwaro::Content::Processors::TemplateEngine.new(ae).env
        render = ->(src : String) { env.from_string(src).render(vars) }
        render.call("{{ content | e }}").should eq("&lt;p&gt;x &amp;amp; y&lt;/p&gt;")
        render.call("{{ content | escape | xml_escape }}").should eq("&amp;lt;p&amp;gt;x &amp;amp;amp; y&amp;lt;/p&amp;gt;")
        env.from_string("{{ content | e }}").render_text(vars).should eq("&lt;p&gt;x &amp;amp; y&lt;/p&gt;")
        if ae
          render.call(%({% set c %}<i>{% endset %}{{ c | e }})).should eq("<i>")
          render.call(%({{ "<b>" | safe | e }})).should eq("<b>")
          render.call("{{ dest | e }}").should eq("/a?b=1&amp;c=2")
        end
      end
    end
  end

  it "r4#8 an engine built without saying otherwise escapes" do
    Hwaro::Content::Processors::TemplateEngine.new.env.from_string("{{ u }}").render(ae_vars).should eq(ESCAPED)
  end

  # Minimal cases from the expression-level differential fuzzer.
  describe "fuzzer cases" do
    it "append/prepend concatenate like ~: a safe side stays markup, the plain side is escaped" do
      on(%({{ s | append(u) }}|{{ s | prepend(u) }}|{{ u | append(s) }}|{{ u | append("<i>") }})).should eq(
        "<i>s&amp;</i>#{ESCAPED}|#{ESCAPED}<i>s&amp;</i>|#{ESCAPED}<i>s&amp;</i>|#{ESCAPED}&lt;i&gt;")
      off(%({{ s | append(u) }}|{{ u | prepend(s) }})).should eq("<i>s&amp;</i>#{CANARY}|<i>s&amp;</i>#{CANARY}")
    end
  end
end
