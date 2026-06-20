require "../spec_helper"

describe Hwaro::Utils::TextUtils do
  describe ".slugify" do
    it "converts basic text to slug" do
      Hwaro::Utils::TextUtils.slugify("Hello World").should eq("hello-world")
    end

    it "converts uppercase to lowercase" do
      Hwaro::Utils::TextUtils.slugify("MY BLOG POST").should eq("my-blog-post")
    end

    it "replaces multiple spaces with single hyphen" do
      Hwaro::Utils::TextUtils.slugify("hello   world").should eq("hello-world")
    end

    it "removes leading and trailing hyphens" do
      Hwaro::Utils::TextUtils.slugify("  hello  ").should eq("hello")
    end

    it "removes punctuation and symbols" do
      Hwaro::Utils::TextUtils.slugify("Hello, World!").should eq("hello-world")
    end

    it "preserves numbers" do
      Hwaro::Utils::TextUtils.slugify("post 123").should eq("post-123")
    end

    it "handles underscores as separators" do
      Hwaro::Utils::TextUtils.slugify("hello_world").should eq("hello-world")
    end

    it "handles hyphens in input" do
      Hwaro::Utils::TextUtils.slugify("hello-world").should eq("hello-world")
    end

    it "collapses mixed separators" do
      Hwaro::Utils::TextUtils.slugify("hello - _ world").should eq("hello-world")
    end

    it "preserves CJK characters" do
      Hwaro::Utils::TextUtils.slugify("한글 제목").should eq("한글-제목")
    end

    it "preserves mixed ASCII and CJK" do
      Hwaro::Utils::TextUtils.slugify("CJK 테스트!").should eq("cjk-테스트")
    end

    it "preserves Japanese hiragana and katakana" do
      Hwaro::Utils::TextUtils.slugify("テスト記事").should eq("テスト記事")
    end

    it "preserves Unicode letters (e.g. accented)" do
      Hwaro::Utils::TextUtils.slugify("café résumé").should eq("café-résumé")
    end

    it "lowercases uppercase Unicode letters" do
      Hwaro::Utils::TextUtils.slugify("CAFÉ").should eq("café")
      Hwaro::Utils::TextUtils.slugify("Über Café").should eq("über-café")
    end

    it "handles empty string" do
      Hwaro::Utils::TextUtils.slugify("").should eq("")
    end

    it "handles string with only symbols" do
      Hwaro::Utils::TextUtils.slugify("!@#$%").should eq("")
    end
  end

  describe ".slugify (extended)" do
    it "handles consecutive separators of mixed types" do
      Hwaro::Utils::TextUtils.slugify("a - _ - b").should eq("a-b")
    end

    it "handles CJK followed immediately by ASCII" do
      Hwaro::Utils::TextUtils.slugify("한글abc").should eq("한글abc")
    end

    it "handles ASCII followed immediately by CJK" do
      Hwaro::Utils::TextUtils.slugify("abc한글").should eq("abc한글")
    end

    it "drops emoji characters" do
      Hwaro::Utils::TextUtils.slugify("Hello 👋 World").should eq("hello-world")
    end

    it "handles very long string" do
      long = "a" * 1000
      Hwaro::Utils::TextUtils.slugify(long).should eq(long)
    end

    it "handles string ending with symbols" do
      Hwaro::Utils::TextUtils.slugify("hello!!!").should eq("hello")
    end

    it "handles only spaces" do
      Hwaro::Utils::TextUtils.slugify("   ").should eq("")
    end

    it "handles Hangul Jamo characters" do
      # ㄱ is in Hangul Jamo range 0x1100-0x11FF
      Hwaro::Utils::TextUtils.slugify("ᄀᄁ test").should eq("ᄀᄁ-test")
    end
  end

  describe ".disambiguated_slugs" do
    it "leaves non-colliding terms unchanged" do
      map = Hwaro::Utils::TextUtils.disambiguated_slugs(["Crystal", "Ruby"])
      map["Crystal"].should eq("crystal")
      map["Ruby"].should eq("ruby")
    end

    it "gives distinct terms that slugify identically unique slugs" do
      map = Hwaro::Utils::TextUtils.disambiguated_slugs(["C++", "C#"])
      # Both base-slugify to "c"; the sorted-first term keeps the base slug.
      map.values.sort!.should eq(["c", "c-2"])
      map["C++"].should_not eq(map["C#"])
    end

    it "is deterministic regardless of input order" do
      a = Hwaro::Utils::TextUtils.disambiguated_slugs(["C#", "C++"])
      b = Hwaro::Utils::TextUtils.disambiguated_slugs(["C++", "C#"])
      a.should eq(b)
    end

    it "does not collide a generated suffix with a real term that already uses it" do
      # "A"/"A " both slugify to "a"; a real "a-2" must not be overwritten.
      map = Hwaro::Utils::TextUtils.disambiguated_slugs(["A", "A ", "a-2"])
      values = map.values
      values.size.should eq(values.uniq.size)
      values.size.should eq(3)
    end
  end

  describe ".encode_url_path" do
    it "leaves plain ASCII URLs unchanged" do
      Hwaro::Utils::TextUtils.encode_url_path("https://example.com/posts/hello/").should eq("https://example.com/posts/hello/")
    end

    it "percent-encodes non-ASCII path segments, keeping scheme and host" do
      Hwaro::Utils::TextUtils.encode_url_path("https://example.com/posts/한글-포스트/")
        .should eq("https://example.com/posts/%ED%95%9C%EA%B8%80-%ED%8F%AC%EC%8A%A4%ED%8A%B8/")
    end

    it "encodes spaces in paths" do
      Hwaro::Utils::TextUtils.encode_url_path("https://example.com/a b/").should eq("https://example.com/a%20b/")
    end

    it "encodes root-relative paths without a scheme" do
      Hwaro::Utils::TextUtils.encode_url_path("/tags/한국어/rss.xml").should eq("/tags/%ED%95%9C%EA%B5%AD%EC%96%B4/rss.xml")
    end

    it "does not double-encode already-encoded URLs" do
      pre = "https://example.com/posts/%ED%95%9C%EA%B8%80/"
      Hwaro::Utils::TextUtils.encode_url_path(pre).should eq(pre)
    end

    it "leaves a bare domain without path unchanged" do
      Hwaro::Utils::TextUtils.encode_url_path("https://한글.example").should eq("https://한글.example")
    end
  end

  describe ".escape_xml" do
    it "escapes ampersand" do
      Hwaro::Utils::TextUtils.escape_xml("Tom & Jerry").should eq("Tom &amp; Jerry")
    end

    it "escapes less than" do
      Hwaro::Utils::TextUtils.escape_xml("<script>").should eq("&lt;script&gt;")
    end

    it "escapes greater than" do
      Hwaro::Utils::TextUtils.escape_xml("a > b").should eq("a &gt; b")
    end

    it "escapes double quote" do
      Hwaro::Utils::TextUtils.escape_xml("say \"hello\"").should eq("say &quot;hello&quot;")
    end

    it "escapes single quote" do
      Hwaro::Utils::TextUtils.escape_xml("it's").should eq("it&apos;s")
    end

    it "escapes all special characters together" do
      Hwaro::Utils::TextUtils.escape_xml("<a href=\"x\">&'</a>").should eq("&lt;a href=&quot;x&quot;&gt;&amp;&apos;&lt;/a&gt;")
    end

    it "returns plain text unchanged" do
      Hwaro::Utils::TextUtils.escape_xml("hello world").should eq("hello world")
    end

    it "handles empty string" do
      Hwaro::Utils::TextUtils.escape_xml("").should eq("")
    end
  end

  describe ".strip_html" do
    it "strips simple tags" do
      Hwaro::Utils::TextUtils.strip_html("<p>Hello</p>").should eq("Hello")
    end

    it "strips nested tags" do
      Hwaro::Utils::TextUtils.strip_html("<p>Hello <b>World</b></p>").should eq("Hello World")
    end

    it "normalizes whitespace" do
      Hwaro::Utils::TextUtils.strip_html("<p>  hello   world  </p>").should eq("hello world")
    end

    it "adds space at tag boundaries between words" do
      Hwaro::Utils::TextUtils.strip_html("<p>Hello</p><p>World</p>").should eq("Hello World")
    end

    it "handles self-closing tags" do
      Hwaro::Utils::TextUtils.strip_html("Hello<br/>World").should eq("Hello World")
    end

    it "returns plain text unchanged" do
      Hwaro::Utils::TextUtils.strip_html("no tags here").should eq("no tags here")
    end

    it "handles empty string" do
      Hwaro::Utils::TextUtils.strip_html("").should eq("")
    end

    it "handles tags with attributes" do
      Hwaro::Utils::TextUtils.strip_html("<a href=\"url\">link</a>").should eq("link")
    end
  end

  describe ".strip_html (extended)" do
    it "handles unclosed tag at end" do
      Hwaro::Utils::TextUtils.strip_html("Hello <b>world").should eq("Hello world")
    end

    it "handles tag-only input" do
      Hwaro::Utils::TextUtils.strip_html("<div><span></span></div>").should eq("")
    end

    it "does not add space before punctuation after tag" do
      Hwaro::Utils::TextUtils.strip_html("Hello</b>!").should eq("Hello!")
    end

    it "handles deeply nested tags" do
      Hwaro::Utils::TextUtils.strip_html("<div><p><span><b><i>deep</i></b></span></p></div>").should eq("deep")
    end

    it "handles multiple consecutive tags" do
      Hwaro::Utils::TextUtils.strip_html("<br/><br/><hr/>Text").should eq("Text")
    end

    it "handles mixed inline and block tags" do
      Hwaro::Utils::TextUtils.strip_html("<p>Para 1</p><p>Para 2</p>").should eq("Para 1 Para 2")
    end

    it "handles tags with complex attributes" do
      Hwaro::Utils::TextUtils.strip_html("<a href=\"url\" class=\"link\" data-x=\"y\">text</a>").should eq("text")
    end

    it "handles > in text content (treated as tag close)" do
      # The simple parser treats < as tag-open and > as tag-close,
      # so bare > in text gets consumed as a tag boundary
      Hwaro::Utils::TextUtils.strip_html("a > b").should eq("a b")
    end

    # Raw-text elements: <style>/<script> bodies are code, not display text,
    # and must be dropped along with their tags. Otherwise the CSS/JS source
    # leaks into search indexes, feed summaries, and excerpts.
    it "drops <style> element bodies, keeping surrounding text" do
      input = "<style>.gallery { display: grid; gap: 10px; }</style><p>Real text</p>"
      Hwaro::Utils::TextUtils.strip_html(input).should eq("Real text")
    end

    it "drops <script> element bodies, keeping surrounding text" do
      input = "<p>Before</p><script>console.log(\"x\"); var y = 1;</script><p>After</p>"
      Hwaro::Utils::TextUtils.strip_html(input).should eq("Before After")
    end

    it "drops multi-line and attributed <style>/<script> blocks" do
      input = <<-HTML
        <style type="text/css">
          .a { color: red; }
          .b { color: blue; }
        </style>
        <h1>Heading</h1>
        <script src="x.js">
          if (a < b) { doThing(); }
        </script>
        Tail
        HTML
      Hwaro::Utils::TextUtils.strip_html(input).should eq("Heading Tail")
    end

    it "is case-insensitive for raw-text element names" do
      input = "<STYLE>.x{}</STYLE><p>Kept</p><SCRIPT>bad()</SCRIPT>"
      Hwaro::Utils::TextUtils.strip_html(input).should eq("Kept")
    end
  end

  describe ".cjk_char?" do
    it "returns true for CJK Unified Ideograph" do
      Hwaro::Utils::TextUtils.cjk_char?('中').should be_true
    end

    it "returns true for Hangul syllable" do
      Hwaro::Utils::TextUtils.cjk_char?('한').should be_true
    end

    it "returns true for Hiragana" do
      Hwaro::Utils::TextUtils.cjk_char?('あ').should be_true
    end

    it "returns true for Katakana" do
      Hwaro::Utils::TextUtils.cjk_char?('ア').should be_true
    end

    it "returns false for ASCII letter" do
      Hwaro::Utils::TextUtils.cjk_char?('a').should be_false
    end

    it "returns false for digit" do
      Hwaro::Utils::TextUtils.cjk_char?('1').should be_false
    end

    it "returns false for accented letter" do
      Hwaro::Utils::TextUtils.cjk_char?('é').should be_false
    end
  end

  describe ".tokenize_cjk" do
    it "splits CJK run into overlapping bigrams" do
      Hwaro::Utils::TextUtils.tokenize_cjk("검색엔진").should eq("검색 색엔 엔진")
    end

    it "preserves non-CJK text" do
      Hwaro::Utils::TextUtils.tokenize_cjk("hello").should eq("hello")
    end

    it "handles mixed CJK and ASCII" do
      Hwaro::Utils::TextUtils.tokenize_cjk("hello世界测试").should eq("hello世界 界测 测试")
    end

    it "handles single CJK character" do
      Hwaro::Utils::TextUtils.tokenize_cjk("中").should eq("中")
    end

    it "handles two CJK characters" do
      Hwaro::Utils::TextUtils.tokenize_cjk("中文").should eq("中文")
    end

    it "handles empty string" do
      Hwaro::Utils::TextUtils.tokenize_cjk("").should eq("")
    end

    it "handles pure ASCII" do
      Hwaro::Utils::TextUtils.tokenize_cjk("abc def").should eq("abc def")
    end

    it "handles multiple CJK runs separated by ASCII" do
      Hwaro::Utils::TextUtils.tokenize_cjk("한글test테스트").should eq("한글test테스 스트")
    end

    it "handles CJK run of exactly 3 characters" do
      Hwaro::Utils::TextUtils.tokenize_cjk("가나다").should eq("가나 나다")
    end

    it "handles mixed hiragana and kanji" do
      Hwaro::Utils::TextUtils.tokenize_cjk("あ漢字").should eq("あ漢 漢字")
    end
  end

  describe ".cjk_char? (extended)" do
    it "returns true for CJK Extension A" do
      # U+3400 is in CJK Extension A range
      Hwaro::Utils::TextUtils.cjk_char?('\u{3400}').should be_true
    end

    it "returns true for CJK Compatibility" do
      # U+3300 is in CJK Compatibility range
      Hwaro::Utils::TextUtils.cjk_char?('\u{3300}').should be_true
    end

    it "returns true for CJK Compatibility Forms" do
      # U+FE30 is in CJK Compatibility Forms range
      Hwaro::Utils::TextUtils.cjk_char?('\u{FE30}').should be_true
    end

    it "returns false for space" do
      Hwaro::Utils::TextUtils.cjk_char?(' ').should be_false
    end

    it "returns false for emoji" do
      Hwaro::Utils::TextUtils.cjk_char?('😀').should be_false
    end
  end
end
