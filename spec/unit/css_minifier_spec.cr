require "../spec_helper"

describe Hwaro::Utils::CssMinifier do
  describe ".minify" do
    # =========================================================================
    # Comment removal — basic
    # =========================================================================
    it "removes CSS comments" do
      css = "body { /* main style */ color: red; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should_not contain("/* main style */")
      result.should contain("color:red")
    end

    it "removes multi-line comments" do
      css = "body {\n  /* this is\n  a multi-line\n  comment */\n  color: red;\n}"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should_not contain("multi-line")
      result.should contain("color:red")
    end

    it "removes multiple comments in one rule" do
      css = "body { /* a */ color: red; /* b */ font-size: 14px; /* c */ }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should_not contain("/* a */")
      result.should_not contain("/* b */")
      result.should_not contain("/* c */")
      result.should contain("color:red")
      result.should contain("font-size:14px")
    end

    it "removes comments between rules" do
      css = ".a { color: red; }\n/* separator */\n.b { color: blue; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should_not contain("separator")
      result.should contain(".a{color:red}")
      result.should contain(".b{color:blue}")
    end

    it "removes adjacent comments" do
      css = "/* comment A *//* comment B */body { color: red; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should_not contain("comment A")
      result.should_not contain("comment B")
      result.should contain("body{color:red}")
    end

    it "removes comment at very start of file" do
      css = "/* header comment */\nbody { color: red; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should_not contain("header comment")
      result.should eq("body{color:red}")
    end

    it "removes comment at very end of file" do
      css = "body { color: red; }\n/* footer comment */"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should_not contain("footer comment")
      result.should eq("body{color:red}")
    end

    it "handles file that is only comments" do
      css = "/* only */\n/* comments */\n/* here */"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should eq("")
    end

    it "handles empty comment" do
      css = "/**/body { color: red; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("body{color:red}")
    end

    it "removes rule body that is only comments" do
      css = "body { /* nothing useful */ }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should eq("body{}")
    end

    # =========================================================================
    # Comment-like patterns inside strings (BUG FIX verification)
    # =========================================================================
    it "preserves comment-like pattern inside double-quoted string" do
      css = %(p::before { content: "/* not a comment */"; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%("/* not a comment */"))
    end

    it "preserves comment-like pattern inside single-quoted string" do
      css = "p::before { content: '/* also not a comment */'; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("'/* also not a comment */'")
    end

    it "preserves star-slash pattern inside string" do
      css = %(p::before { content: "a */ b /* c"; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%("a */ b /* c"))
    end

    # =========================================================================
    # Whitespace collapsing
    # =========================================================================
    it "collapses whitespace" do
      css = "body  {\n  color:  red;\n  font-size:  14px;\n}"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should_not contain("\n")
    end

    it "collapses tabs and mixed whitespace" do
      css = "body\t\t{\n\t\tcolor:\t\tred;\n}"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should_not contain("\t")
      result.should contain("color:red")
    end

    it "handles CRLF line endings" do
      css = "body {\r\n  color: red;\r\n}\r\n"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should_not contain("\r")
      result.should_not contain("\n")
      result.should contain("body{color:red}")
    end

    # =========================================================================
    # Structural character handling
    # =========================================================================
    it "removes whitespace around structural characters" do
      css = "body { color : red ; font-size : 14px ; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("color:red")
      result.should contain("font-size:14px")
    end

    it "strips trailing semicolons before }" do
      css = "body { color: red; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("color:red}")
      result.should_not contain(";}")
    end

    it "removes whitespace around commas in selectors" do
      css = "h1 , h2 , h3 { color: red; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("h1,h2,h3{")
    end

    it "handles empty rule body" do
      css = "body { }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should eq("body{}")
    end

    # =========================================================================
    # Empty and degenerate input
    # =========================================================================
    it "handles empty input" do
      Hwaro::Utils::CssMinifier.minify("").should eq("")
    end

    it "handles whitespace-only input" do
      Hwaro::Utils::CssMinifier.minify("   \n\t  \n  ").should eq("")
    end

    it "handles single character input" do
      Hwaro::Utils::CssMinifier.minify("x").should eq("x")
    end

    it "preserves functional CSS that is already minified" do
      css = ".btn{background:#fff;border:1px solid #ccc}"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should eq(css)
    end

    # =========================================================================
    # URL preservation
    # =========================================================================
    it "preserves url() with http protocol" do
      css = "body { background: url(http://example.com/image.png); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("url(http://example.com/image.png)")
    end

    it "preserves url() with https protocol" do
      css = "body { background: url('https://example.com/image.png'); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("url('https://example.com/image.png')")
    end

    it "preserves url() with double-quoted https" do
      css = %(body { background: url("https://cdn.example.com/bg.jpg"); })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%(url("https://cdn.example.com/bg.jpg")))
    end

    it "preserves url() with data URI (svg)" do
      css = %(body { background: url("data:image/svg+xml;charset=utf-8,%3Csvg%3E"); })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("data:image/svg+xml")
    end

    it "preserves url() with data URI (base64)" do
      css = %(.icon { background: url(data:image/png;base64,iVBORw0KGgo=); })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("url(data:image/png;base64,iVBORw0KGgo=)")
    end

    it "preserves url() with spaces around path" do
      css = "body { background: url(  '/images/bg.png'  ); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("url('/images/bg.png')")
    end

    it "preserves multiple url() values in one rule" do
      css = ".x { background: url(http://a.com/1.png), url(http://b.com/2.png); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("url(http://a.com/1.png)")
      result.should contain("url(http://b.com/2.png)")
    end

    it "preserves url() in @font-face src" do
      css = %(@font-face { font-family: "MyFont"; src: url("https://fonts.example.com/font.woff2") format("woff2"); })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%(url("https://fonts.example.com/font.woff2")))
    end

    it "preserves url() with relative path" do
      css = "body { background: url(../images/bg.png); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("url(../images/bg.png)")
    end

    it "preserves url() with query string" do
      css = "body { background: url('/img.png?v=123&w=100'); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("url('/img.png?v=123&w=100')")
    end

    it "preserves url() with hash fragment" do
      css = "body { background: url('sprite.svg#icon'); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("url('sprite.svg#icon')")
    end

    it "preserves url() in @import" do
      css = %(@import url("https://fonts.googleapis.com/css2?family=Open+Sans");\nbody { font-family: "Open Sans"; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%(url("https://fonts.googleapis.com/css2?family=Open+Sans")))
    end

    it "preserves multiple url() in background shorthand" do
      css = ".bg { background: url('img.png') no-repeat, linear-gradient(to right, #000, #fff); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("url('img.png')")
    end

    # =========================================================================
    # String literal preservation
    # =========================================================================
    it "preserves double-quoted strings in content property" do
      css = %(p::before { content: "hello : world"; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%("hello : world"))
    end

    it "preserves single-quoted strings in content property" do
      css = "p::after { content: 'spacing { test }'; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("'spacing { test }'")
    end

    it "preserves strings with semicolons" do
      css = %(p::before { content: "a; b; c"; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%("a; b; c"))
    end

    it "preserves strings with commas" do
      css = %(p::before { content: "a , b , c"; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%("a , b , c"))
    end

    it "preserves strings with braces" do
      css = %(p::before { content: "{ some { nested } }"; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%("{ some { nested } }"))
    end

    it "preserves escaped quotes in double-quoted strings" do
      css = %(p::before { content: "say \\"hello\\""; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("say \\\"hello\\\"")
    end

    it "preserves escaped quotes in single-quoted strings" do
      css = "p::before { content: 'it\\'s fine'; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("it\\'s fine")
    end

    it "preserves empty strings" do
      css = %(p::before { content: ""; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%(""))
    end

    it "preserves single-char strings" do
      css = %(p::before { content: "x"; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%("x"))
    end

    it "preserves string with colon and space" do
      css = %(p::before { content: "key : value"; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%("key : value"))
    end

    it "preserves mixed quote types across declarations" do
      css = %(.a::before { content: "double"; } .b::after { content: 'single'; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%("double"))
      result.should contain("'single'")
    end

    it "preserves string with newlines (escaped)" do
      css = %(p::before { content: "line1\\Aline2"; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%("line1\\Aline2"))
    end

    # =========================================================================
    # Pseudo-elements and pseudo-classes
    # =========================================================================
    it "preserves double-colon pseudo-elements ::before" do
      css = "p::before { content: ''; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("p::before")
    end

    it "preserves ::after pseudo-element" do
      css = "p::after { content: ''; display: block; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("p::after")
    end

    it "preserves ::placeholder pseudo-element" do
      css = "input::placeholder { color: #999; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("input::placeholder")
    end

    it "preserves ::selection pseudo-element" do
      css = "::selection { background: #b3d4fc; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("::selection")
    end

    it "preserves :hover pseudo-class" do
      css = "a:hover { color: blue; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("a:hover{color:blue}")
    end

    it "preserves :nth-child selector" do
      css = "li:nth-child(2n+1) { color: red; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(":nth-child(2n+1)")
    end

    it "preserves :not() pseudo-class" do
      css = "p:not(.special) { color: gray; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("p:not(.special)")
    end

    it "preserves :is() pseudo-class" do
      css = ":is(h1, h2, h3) { font-weight: bold; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(":is(h1,h2,h3)")
    end

    it "preserves :where() pseudo-class" do
      css = ":where(.a, .b) { margin: 0; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(":where(.a,.b)")
    end

    it "preserves :first-child and :last-child" do
      css = "li:first-child { margin-top: 0; } li:last-child { margin-bottom: 0; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(":first-child")
      result.should contain(":last-child")
    end

    # =========================================================================
    # CSS custom properties (variables)
    # =========================================================================
    it "preserves CSS custom property declarations" do
      css = ":root { --main-color: #333; --spacing: 16px; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("--main-color:#333")
      result.should contain("--spacing:16px")
    end

    it "preserves var() function calls" do
      css = "body { color: var(--main-color); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("var(--main-color)")
    end

    it "preserves var() with fallback" do
      css = "body { color: var(--main-color, #333); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("var(--main-color,#333)")
    end

    it "preserves many custom properties on :root" do
      css = ":root {\n  --c1: #111;\n  --c2: #222;\n  --c3: #333;\n  --s1: 8px;\n  --s2: 16px;\n}"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("--c1:#111")
      result.should contain("--s2:16px")
    end

    # =========================================================================
    # Media queries
    # =========================================================================
    it "minifies media query blocks" do
      css = "@media (min-width: 768px) {\n  body { font-size: 16px; }\n}"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("@media")
      result.should contain("font-size:16px")
    end

    it "preserves media query colons" do
      css = "@media screen and (max-width: 600px) { .x { display: none; } }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("max-width:600px")
    end

    it "handles nested @media content" do
      css = "@media print {\n  @media (color) {\n    body { color: black; }\n  }\n}"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("@media print")
      result.should contain("@media (color)")
      result.should contain("color:black")
    end

    # =========================================================================
    # At-rules
    # =========================================================================
    it "preserves @charset" do
      css = "@charset \"UTF-8\";\nbody { color: red; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("@charset")
      result.should contain("\"UTF-8\"")
    end

    it "preserves @supports" do
      css = "@supports (display: grid) { .grid { display: grid; } }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("@supports")
      result.should contain("display:grid")
    end

    it "preserves @layer" do
      css = "@layer base { body { margin: 0; } }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("@layer")
      result.should contain("margin:0")
    end

    it "handles @keyframes" do
      css = "@keyframes slide {\n  0% { transform: translateX(0); }\n  100% { transform: translateX(100px); }\n}"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("@keyframes slide")
      result.should contain("translateX(0)")
      result.should contain("translateX(100px)")
    end

    # =========================================================================
    # CSS functions
    # =========================================================================
    it "handles calc() expressions" do
      css = ".box { width: calc(100% - 20px); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("calc(100% - 20px)")
    end

    it "handles min()/max()/clamp() functions" do
      css = ".box { width: clamp(200px, 50%, 800px); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("clamp(200px,50%,800px)")
    end

    it "handles rgb() function" do
      css = "body { color: rgb(255, 0, 0); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("rgb(255,0,0)")
    end

    it "handles rgba() function" do
      css = "body { color: rgba(0, 0, 0, 0.5); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("rgba(0,0,0,0.5)")
    end

    it "handles linear-gradient()" do
      css = ".bg { background: linear-gradient(to right, #000, #fff); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("linear-gradient(to right,#000,#fff)")
    end

    # =========================================================================
    # Complex selectors
    # =========================================================================
    it "handles nested selectors with combinators" do
      css = ".parent .child > .grandchild { color: red; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(".parent .child > .grandchild{color:red}")
    end

    it "handles attribute selectors with quotes" do
      css = %(input[type="text"] { border: 1px solid #ccc; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%(input[type="text"]))
    end

    it "handles attribute selectors with single quotes" do
      css = "input[type='email'] { border: 1px solid blue; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("input[type='email']")
    end

    it "handles adjacent sibling combinator" do
      css = "h1 + p { margin-top: 0; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("h1 + p{margin-top:0}")
    end

    it "handles general sibling combinator" do
      css = "h1 ~ p { color: gray; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("h1 ~ p{color:gray}")
    end

    # =========================================================================
    # Keyword preservation
    # =========================================================================
    it "preserves !important" do
      css = "body { color: red !important; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("!important")
    end

    it "preserves !important with whitespace variations" do
      css = "body { color: red  !important ; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("!important")
    end

    # =========================================================================
    # Grid template areas (string-heavy)
    # =========================================================================
    it "preserves grid-template-areas with quoted strings" do
      css = %(.grid { grid-template-areas: "header header" "sidebar main" "footer footer"; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%("header header"))
      result.should contain(%("sidebar main"))
      result.should contain(%("footer footer"))
    end

    # =========================================================================
    # Unicode
    # =========================================================================
    it "handles unicode in selectors" do
      css = ".日本語 { color: red; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(".日本語{color:red}")
    end

    it "handles unicode in values" do
      css = %(p::before { content: "→ "; })
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(%("→ "))
    end

    it "handles unicode content escape sequences" do
      css = "p::before { content: \"\\2192\"; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("\"\\2192\"")
    end

    # =========================================================================
    # Real-world complex CSS
    # =========================================================================
    it "handles multiple rules" do
      css = <<-CSS
        body {
          margin: 0;
          padding: 0;
        }
        .container {
          max-width: 1200px;
          margin: 0 auto;
        }
        CSS
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("body{margin:0;padding:0}")
      result.should contain(".container{max-width:1200px;margin:0 auto}")
    end

    it "handles font shorthand with slash" do
      css = "body { font: 400 16px/1.5 \"Arial\", sans-serif; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("16px/1.5")
      result.should contain("\"Arial\"")
    end

    it "handles complex background shorthand" do
      css = ".hero {\n  background:\n    url('overlay.png') center/cover no-repeat,\n    url('bg.jpg') center/cover no-repeat;\n}"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("url('overlay.png')")
      result.should contain("url('bg.jpg')")
    end

    it "handles many selectors in a comma list" do
      css = "h1, h2, h3, h4, h5, h6 { margin: 0; padding: 0; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("h1,h2,h3,h4,h5,h6{")
    end

    it "handles vendor-prefixed properties" do
      css = ".box { -webkit-transform: rotate(45deg); -ms-transform: rotate(45deg); transform: rotate(45deg); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("-webkit-transform:rotate(45deg)")
      result.should contain("-ms-transform:rotate(45deg)")
    end

    it "handles multiple border-radius values" do
      css = ".box { border-radius: 10px 20px 30px 40px / 5px 10px 15px 20px; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("border-radius:10px 20px 30px 40px / 5px 10px 15px 20px")
    end

    it "idempotent: minifying already-minified CSS produces same output" do
      css = "body{color:red;font-size:14px}.a{margin:0}"
      pass1 = Hwaro::Utils::CssMinifier.minify(css)
      pass2 = Hwaro::Utils::CssMinifier.minify(pass1)
      pass1.should eq(pass2)
    end

    it "handles large CSS with many rules" do
      rules = (1..100).map { |i| ".class-#{i} { color: ##{"%06x" % (i * 137)}; }" }.join("\n")
      result = Hwaro::Utils::CssMinifier.minify(rules)
      result.should contain(".class-1{")
      result.should contain(".class-100{")
      result.should_not contain("\n")
    end

    it "handles nested calc() expressions" do
      css = ".box { width: calc(100% - calc(2 * 20px)); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("calc(100% - calc(2 * 20px))")
    end

    it "handles url() without quotes" do
      css = "body { background: url(image.png); }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("url(image.png)")
    end

    it "handles @import with string (no url)" do
      css = "@import \"base.css\";\nbody { color: red; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("\"base.css\"")
      result.should contain("color:red")
    end

    it "handles CSS with only whitespace between rules" do
      css = ".a { color: red; }    .b { color: blue; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(".a{color:red}")
      result.should contain(".b{color:blue}")
    end

    it "handles comment inside url() value (preserved)" do
      css = "body { background: url('path/to/file.png'); /* actual comment */ }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("url('path/to/file.png')")
      result.should_not contain("actual comment")
    end

    # =========================================================================
    # Descendant combinator preservation
    # =========================================================================
    it "preserves space before pseudo-class in descendant combinator" do
      css = "div :hover { color: red; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("div :hover")
    end

    it "preserves space before pseudo-class in complex selector" do
      css = ".container :first-child { margin: 0; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain(".container :first-child")
    end

    it "still removes colon spaces inside declaration blocks" do
      css = "div :hover { color : red ; }"
      result = Hwaro::Utils::CssMinifier.minify(css)
      result.should contain("color:red")
    end
  end
end
