require "../spec_helper"

describe Hwaro::Utils::JsMinifier do
  describe ".minify" do
    # =========================================================================
    # Single-line comment removal
    # =========================================================================
    it "removes single-line comments" do
      js = "var x = 1; // this is a comment\nvar y = 2;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("// this is a comment")
      result.should contain("var x = 1;")
      result.should contain("var y = 2;")
    end

    it "removes single-line comment at start of line" do
      js = "// full line comment\nvar x = 1;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("full line comment")
      result.should contain("var x = 1;")
    end

    it "removes multiple single-line comments" do
      js = "var a = 1; // comment 1\nvar b = 2; // comment 2\nvar c = 3;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("comment 1")
      result.should_not contain("comment 2")
      result.should contain("var a = 1;")
      result.should contain("var c = 3;")
    end

    it "removes single-line comment at very start of file" do
      js = "// first line\nvar x = 1;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("first line")
      result.should contain("var x = 1;")
    end

    it "removes single-line comment at end of file without trailing newline" do
      js = "var x = 1; // end"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("// end")
      result.should contain("var x = 1;")
    end

    it "removes consecutive single-line comments" do
      js = "// line 1\n// line 2\n// line 3\nvar x = 1;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("line 1")
      result.should_not contain("line 2")
      result.should_not contain("line 3")
      result.should contain("var x = 1;")
    end

    # =========================================================================
    # Multi-line comment removal
    # =========================================================================
    it "removes multi-line comments" do
      js = "var x = 1; /* multi\nline\ncomment */ var y = 2;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("multi")
      result.should contain("var x = 1;")
      result.should contain("var y = 2;")
    end

    it "removes JSDoc-style comments" do
      js = "/**\n * @param {string} name\n * @returns {void}\n */\nfunction greet(name) {}"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("@param")
      result.should contain("function greet(name)")
    end

    it "removes inline multi-line comment" do
      js = "var x = /* inline */ 5;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("inline")
      result.should contain("5;")
    end

    it "removes empty multi-line comment" do
      js = "/**/var x = 1;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("var x = 1;")
    end

    it "removes adjacent multi-line comments" do
      js = "/* first *//* second */var x = 1;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("first")
      result.should_not contain("second")
      result.should contain("var x = 1;")
    end

    it "handles unterminated multi-line comment at end" do
      js = "var x = 1; /* unclosed"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("var x = 1;")
    end

    it "removes comment with stars inside" do
      js = "/*** stars ***/\nvar x = 1;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("stars")
      result.should contain("var x = 1;")
    end

    # =========================================================================
    # Mixed comment styles
    # =========================================================================
    it "removes both single and multi-line comments" do
      js = "var a = 1; // single\nvar b = /* multi */ 2;\nvar c = 3; // another"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("single")
      result.should_not contain("multi")
      result.should_not contain("another")
      result.should contain("var a = 1;")
      result.should contain("var b =  2;")
      result.should contain("var c = 3;")
    end

    # =========================================================================
    # Double-quoted string preservation
    # =========================================================================
    it "preserves strings with // inside" do
      js = %{var url = "http://example.com";}
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("http://example.com")
    end

    it "preserves strings with /* inside" do
      js = %{var s = "/* not a comment */";}
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("/* not a comment */")
    end

    it "preserves strings with escaped double quotes" do
      js = %{var s = "he said \\"hello\\"";}
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("he said \\\"hello\\\"")
    end

    it "preserves empty double-quoted strings" do
      js = %{var s = "";}
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain(%{""})
    end

    it "preserves strings with backslashes" do
      js = %{var s = "path\\\\to\\\\file";}
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("path\\\\to\\\\file")
    end

    it "preserves string with backslash-n" do
      js = %{var s = "line1\\nline2";}
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("line1\\nline2")
    end

    # =========================================================================
    # Single-quoted string preservation
    # =========================================================================
    it "preserves single-quoted strings with //" do
      js = "var url = 'http://example.com';"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("http://example.com")
    end

    it "preserves escaped single quotes inside single-quoted string" do
      js = "var s = 'it\\'s fine';"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("it\\'s fine")
    end

    it "preserves empty single-quoted strings" do
      js = "var s = '';"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("''")
    end

    # =========================================================================
    # Template literal preservation
    # =========================================================================
    it "preserves template literals" do
      js = "var s = `hello ${name}`;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("`hello ${name}`")
    end

    it "preserves template literal with // inside" do
      js = "var s = `http://example.com/${path}`;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("http://example.com/${path}")
    end

    it "preserves multi-line template literals" do
      js = "var s = `line1\nline2\nline3`;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("`line1\nline2\nline3`")
    end

    it "preserves template literal with escaped backtick" do
      js = "var s = `value is \\`quoted\\``;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("\\`quoted\\`")
    end

    it "preserves empty template literal" do
      js = "var s = ``;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("``")
    end

    it "preserves template literal with /* */ inside" do
      js = "var s = `/* template comment */`;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("/* template comment */")
    end

    it "preserves template literal with complex interpolation" do
      js = "var s = `${a + b} and ${fn(c)}`;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("${a + b}")
      result.should contain("${fn(c)}")
    end

    # =========================================================================
    # Consecutive string and comment
    # =========================================================================
    it "handles string followed by comment on same line" do
      js = %{var s = "value"; // comment\nvar t = "other";}
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain(%{var s = "value";})
      result.should_not contain("comment")
      result.should contain(%{var t = "other";})
    end

    it "handles comment followed by string" do
      js = "/* comment */var s = 'hello';"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("comment")
      result.should contain("var s = 'hello';")
    end

    it "handles adjacent strings" do
      js = %{var a = "one" + "two";}
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain(%{"one"})
      result.should contain(%{"two"})
    end

    # =========================================================================
    # Blank line handling
    # =========================================================================
    it "removes blank lines" do
      js = "var x = 1;\n\n\n\nvar y = 2;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("\n\n")
    end

    it "removes trailing whitespace from lines" do
      js = "var x = 1;   \nvar y = 2;  "
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.lines.each do |line|
        line.should eq(line.rstrip)
      end
    end

    it "removes lines that become empty after comment removal" do
      js = "var x = 1;\n// removed\nvar y = 2;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should eq("var x = 1;\nvar y = 2;")
    end

    # =========================================================================
    # Edge cases — empty/degenerate input
    # =========================================================================
    it "handles empty input" do
      Hwaro::Utils::JsMinifier.minify("").should eq("")
    end

    it "handles whitespace-only input" do
      Hwaro::Utils::JsMinifier.minify("   \n\n   \n  ").should eq("")
    end

    it "handles single-line-comment-only input" do
      Hwaro::Utils::JsMinifier.minify("// just a comment").should eq("")
    end

    it "handles multi-line-comment-only input" do
      Hwaro::Utils::JsMinifier.minify("/* just\na\ncomment */").should eq("")
    end

    it "handles single character input" do
      Hwaro::Utils::JsMinifier.minify("x").should eq("x")
    end

    it "handles input that is just a string" do
      js = %{"hello"}
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should eq(%{"hello"})
    end

    it "handles input that is just a number" do
      Hwaro::Utils::JsMinifier.minify("42").should eq("42")
    end

    # =========================================================================
    # Operators involving /
    # =========================================================================
    it "preserves division operator" do
      js = "var x = 10 / 2;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("10 / 2")
    end

    it "preserves /= assignment operator" do
      js = "x /= 2;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("x /= 2;")
    end

    it "preserves division in expression" do
      js = "var ratio = width / height;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("width / height")
    end

    # =========================================================================
    # Real-world JS patterns
    # =========================================================================
    it "handles function declarations" do
      js = "function greet(name) {\n  // Say hello\n  console.log('Hello ' + name);\n}"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("Say hello")
      result.should contain("function greet(name)")
      result.should contain("console.log")
    end

    it "handles arrow functions" do
      js = "const add = (a, b) => a + b; // adds two numbers"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("adds two numbers")
      result.should contain("const add = (a, b) => a + b;")
    end

    it "handles object literals" do
      js = "var obj = {\n  // Key\n  key: 'value',\n  num: 42\n};"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("// Key")
      result.should contain("key: 'value'")
    end

    it "handles async/await" do
      js = "async function fetch() {\n  // Get data\n  const res = await get('/api');\n  return res;\n}"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("Get data")
      result.should contain("async function")
      result.should contain("await get")
    end

    it "handles class definition" do
      js = "class Foo {\n  // constructor\n  constructor() {\n    this.x = 1;\n  }\n}"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("// constructor")
      result.should contain("class Foo")
      result.should contain("this.x = 1;")
    end

    it "handles destructuring" do
      js = "const { a, b } = obj; // destructure"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("destructure")
      result.should contain("const { a, b } = obj;")
    end

    it "handles ternary operator" do
      js = "var x = a > b ? a : b; // max"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("// max")
      result.should contain("a > b ? a : b")
    end

    it "preserves JSON-like content" do
      js = %{var config = {"url": "http://api.example.com", "timeout": 5000};}
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain(%{"url": "http://api.example.com"})
      result.should contain(%{"timeout": 5000})
    end

    it "handles regex-like pattern in string" do
      js = %{var pattern = "/test/gi";}
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain(%{"/test/gi"})
    end

    it "handles switch statement" do
      js = "switch(x) {\n  case 1: // first\n    break;\n  default:\n    break;\n}"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("// first")
      result.should contain("case 1:")
    end

    it "handles for loop" do
      js = "for (var i = 0; i < 10; i++) {\n  // loop\n  console.log(i);\n}"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("// loop")
      result.should contain("i < 10")
    end

    # =========================================================================
    # Unicode
    # =========================================================================
    it "preserves unicode in strings" do
      js = %{var name = "한글 이름";}
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain(%{"한글 이름"})
    end

    it "preserves unicode in identifiers" do
      js = "var π = 3.14159;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("var π = 3.14159;")
    end

    it "preserves emoji in strings" do
      js = %{var msg = "Hello 👋 World";}
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain(%{"Hello 👋 World"})
    end

    # =========================================================================
    # CRLF handling
    # =========================================================================
    it "handles CRLF line endings" do
      js = "var x = 1; // comment\r\nvar y = 2;\r\n"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should_not contain("// comment")
      result.should contain("var x = 1;")
      result.should contain("var y = 2;")
    end

    # =========================================================================
    # Idempotence
    # =========================================================================
    it "idempotent: minifying already-minified JS produces same output" do
      js = "var x = 1;\nvar y = 2;\nfunction f(a) { return a; }"
      pass1 = Hwaro::Utils::JsMinifier.minify(js)
      pass2 = Hwaro::Utils::JsMinifier.minify(pass1)
      pass1.should eq(pass2)
    end

    # =========================================================================
    # Large input
    # =========================================================================
    it "handles large JS with many lines" do
      lines = (1..200).map { |i| "var v#{i} = #{i}; // comment #{i}" }
      js = lines.join("\n")
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("var v1 = 1;")
      result.should contain("var v200 = 200;")
      result.should_not contain("// comment")
    end

    # =========================================================================
    # Unterminated constructs
    # =========================================================================
    it "handles unterminated string at end of input" do
      js = %{var s = "unterminated}
      result = Hwaro::Utils::JsMinifier.minify(js)
      # Should not crash, output something reasonable
      result.should contain("var s = ")
    end

    it "handles unterminated single-quoted string" do
      js = "var s = 'unterminated"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("var s = ")
    end

    it "handles unterminated template literal" do
      js = "var s = `unterminated"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("var s = ")
    end

    it "handles */ without opening /*" do
      js = "var x = 1; */ var y = 2;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("var x = 1;")
      # The */ is just literal characters
      result.should contain("*/")
    end

    it "handles nested braces inside template literal interpolation" do
      js = "var s = `${obj.map(x => { return x; })}`;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("`${obj.map(x => { return x; })}`")
    end

    it "handles multiple template literal interpolations" do
      js = "var s = `${a} + ${b} = ${a + b}`;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("${a}")
      result.should contain("${b}")
      result.should contain("${a + b}")
    end

    it "handles comment-like pattern in template literal" do
      js = "var s = `// not a comment\n/* also not */`;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("// not a comment")
      result.should contain("/* also not */")
    end

    it "preserves regex-like division after parenthesis" do
      js = "var x = (a + b) / c;"
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("(a + b) / c")
    end

    it "handles string with backslash at end" do
      js = %{var s = "end\\\\"; var x = 1;}
      result = Hwaro::Utils::JsMinifier.minify(js)
      result.should contain("var x = 1;")
    end
  end
end
