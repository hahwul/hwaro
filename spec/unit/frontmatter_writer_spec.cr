require "../spec_helper"

# FrontmatterWriter is the single source of truth for how `tool convert`,
# `tool export` and every importer serialize frontmatter back to disk. Its
# rules are byte-level contracts (TOML key quoting, string escaping, date
# emission), so they are pinned here directly rather than only through the
# commands that happen to call them.
private def toml_build(fields : Hash(String, YAML::Any)) : String
  Hwaro::Utils::FrontmatterWriter::TomlBuilder.new.build(fields)
end

private def yaml_any(value) : YAML::Any
  YAML.parse(value.to_yaml)
end

describe Hwaro::Utils::FrontmatterWriter do
  describe ".serialize_time" do
    # The whole reason this helper exists: `to_rfc3339` converts to UTC, so a
    # local date in any positive-offset zone rolls back a calendar day.
    it "emits a bare date when the value carries no time-of-day" do
      time = Time.local(2026, 5, 20, 0, 0, 0, location: Time::Location.fixed(9 * 3600))
      Hwaro::Utils::FrontmatterWriter.serialize_time(time).should eq("2026-05-20")
    end

    it "emits a bare date for a midnight UTC value too" do
      time = Time.utc(2026, 5, 20, 0, 0, 0)
      Hwaro::Utils::FrontmatterWriter.serialize_time(time).should eq("2026-05-20")
    end

    it "keeps a non-zero offset instead of normalizing to UTC" do
      time = Time.local(2026, 5, 20, 8, 0, 0, location: Time::Location.fixed(9 * 3600))
      Hwaro::Utils::FrontmatterWriter.serialize_time(time).should eq("2026-05-20T08:00:00+09:00")
    end

    it "does not roll a positive-offset morning back to the previous day" do
      time = Time.local(2026, 5, 20, 8, 0, 0, location: Time::Location.fixed(9 * 3600))
      Hwaro::Utils::FrontmatterWriter.serialize_time(time).should start_with("2026-05-20")
    end

    it "uses rfc3339 for genuine UTC timestamps" do
      time = Time.utc(2026, 5, 20, 8, 30, 15)
      Hwaro::Utils::FrontmatterWriter.serialize_time(time).should eq("2026-05-20T08:30:15Z")
    end

    it "treats a sub-second-only value as a timestamp, not a date" do
      time = Time.utc(2026, 5, 20, 0, 0, 0) + 500.milliseconds
      Hwaro::Utils::FrontmatterWriter.serialize_time(time).should_not eq("2026-05-20")
    end

    it "renders a negative offset" do
      time = Time.local(2026, 5, 20, 8, 0, 0, location: Time::Location.fixed(-5 * 3600))
      Hwaro::Utils::FrontmatterWriter.serialize_time(time).should eq("2026-05-20T08:00:00-05:00")
    end
  end

  describe ".escape_toml_string" do
    it "escapes backslashes before quotes so the result is not double-escaped" do
      Hwaro::Utils::FrontmatterWriter.escape_toml_string(%q(a\b)).should eq(%q(a\\b))
    end

    it "escapes double quotes" do
      Hwaro::Utils::FrontmatterWriter.escape_toml_string(%q(say "hi")).should eq(%q(say \"hi\"))
    end

    it "escapes newline, tab and carriage return" do
      Hwaro::Utils::FrontmatterWriter.escape_toml_string("a\nb\tc\rd").should eq("a\\nb\\tc\\rd")
    end

    # `String#inspect` would emit `\a` / `\e` / `\v`, none of which TOML accepts.
    it "escapes control characters with \\uXXXX rather than TOML-invalid short escapes" do
      Hwaro::Utils::FrontmatterWriter.escape_toml_string("bell").should eq("bell\\u0007")
      Hwaro::Utils::FrontmatterWriter.escape_toml_string("esc").should eq("esc\\u001B")
      Hwaro::Utils::FrontmatterWriter.escape_toml_string("vt").should eq("vt\\u000B")
    end

    it "escapes DEL" do
      Hwaro::Utils::FrontmatterWriter.escape_toml_string("x").should eq("x\\u007F")
    end

    # toml.cr's \uXXXX reader greedily eats a following hex digit, so escaping
    # non-ASCII would corrupt "Auto<ZWSP>build" into an unparseable file.
    it "leaves non-ASCII text raw" do
      Hwaro::Utils::FrontmatterWriter.escape_toml_string("한글 café").should eq("한글 café")
    end

    it "leaves a zero-width space raw" do
      Hwaro::Utils::FrontmatterWriter.escape_toml_string("Auto​build").should eq("Auto​build")
    end

    it "round-trips through a TOML parser" do
      original = "quote \" backslash \\ tab \t bell  한글"
      escaped = Hwaro::Utils::FrontmatterWriter.escape_toml_string(original)
      TOML.parse(%(k = "#{escaped}"))["k"].should eq(original)
    end
  end

  describe ".format_toml_key" do
    it "leaves a bare key unquoted" do
      Hwaro::Utils::FrontmatterWriter.format_toml_key("my_key-1").should eq("my_key-1")
    end

    it "quotes a key containing a dot, which TOML would read as a path" do
      Hwaro::Utils::FrontmatterWriter.format_toml_key("a.b").should eq(%q("a.b"))
    end

    it "quotes a key containing a space" do
      Hwaro::Utils::FrontmatterWriter.format_toml_key("my key").should eq(%q("my key"))
    end

    it "quotes a non-ASCII key" do
      Hwaro::Utils::FrontmatterWriter.format_toml_key("제목").should eq(%q("제목"))
    end

    it "quotes an empty key" do
      Hwaro::Utils::FrontmatterWriter.format_toml_key("").should eq(%q(""))
    end

    it "escapes a quote inside a quoted key" do
      Hwaro::Utils::FrontmatterWriter.format_toml_key(%q(a"b)).should eq(%q("a\"b"))
    end
  end

  describe ".yaml_scalar" do
    it "leaves a simple identifier-like value bare" do
      Hwaro::Utils::FrontmatterWriter.yaml_scalar("hello-world").should eq("hello-world")
    end

    it "leaves an internal space bare" do
      Hwaro::Utils::FrontmatterWriter.yaml_scalar("My Post Title").should eq("My Post Title")
    end

    # `beta: gamma` parses as a nested mapping when left bare.
    it "quotes a value containing a colon" do
      Hwaro::Utils::FrontmatterWriter.yaml_scalar("beta: gamma").should eq(%q("beta: gamma"))
    end

    it "quotes YAML 1.1 boolean-ish words in any casing" do
      %w[true false yes no on off null none y n ~].each do |word|
        Hwaro::Utils::FrontmatterWriter.yaml_scalar(word).should eq(%("#{word}"))
      end
      Hwaro::Utils::FrontmatterWriter.yaml_scalar("NO").should eq(%q("NO"))
      Hwaro::Utils::FrontmatterWriter.yaml_scalar("Yes").should eq(%q("Yes"))
    end

    it "quotes a date-shaped value so YAML does not reparse it as a date" do
      Hwaro::Utils::FrontmatterWriter.yaml_scalar("2024-01-15").should eq(%q("2024-01-15"))
    end

    it "quotes an alias/anchor sigil" do
      Hwaro::Utils::FrontmatterWriter.yaml_scalar("*x").should eq(%q("*x"))
      Hwaro::Utils::FrontmatterWriter.yaml_scalar("&x").should eq(%q("&x"))
    end

    it "quotes a value with a trailing space" do
      Hwaro::Utils::FrontmatterWriter.yaml_scalar("trailing ").should eq(%q("trailing "))
    end

    it "quotes an empty string" do
      Hwaro::Utils::FrontmatterWriter.yaml_scalar("").should eq(%q(""))
    end

    it "quotes a non-ASCII value" do
      Hwaro::Utils::FrontmatterWriter.yaml_scalar("한글").should eq(%q("한글"))
    end

    # YAML rejects Crystal's brace form (`\u{E0001}`) — only the fixed-width
    # forms are legal.
    it "escapes unprintable codepoints with fixed-width forms only" do
      Hwaro::Utils::FrontmatterWriter.yaml_scalar("ab").should eq(%q("a\x07b"))
      Hwaro::Utils::FrontmatterWriter.yaml_scalar("a\u{200B}b").should eq(%q("a\u200Bb"))
      Hwaro::Utils::FrontmatterWriter.yaml_scalar("a\u{E0001}b").should eq(%q("a\U000E0001b"))
    end

    it "never emits the brace escape form YAML cannot read" do
      Hwaro::Utils::FrontmatterWriter.yaml_scalar("a\u{E0001}b").should_not contain("\\u{")
    end

    it "escapes quote, backslash and whitespace controls" do
      Hwaro::Utils::FrontmatterWriter.yaml_scalar(%(a"b\\c\nd\te\rf))
        .should eq(%q("a\"b\\c\nd\te\rf"))
    end

    it "round-trips quoted output through a YAML parser" do
      ["beta: gamma", "NO", "2024-01-15", "*x", "ab", ""].each do |value|
        YAML.parse("k: #{Hwaro::Utils::FrontmatterWriter.yaml_scalar(value)}")["k"].as_s.should eq(value)
      end
    end

    it "round-trips bare output through a YAML parser" do
      ["hello-world", "My Post Title", "a/b", "v1.2"].each do |value|
        YAML.parse("k: #{Hwaro::Utils::FrontmatterWriter.yaml_scalar(value)}")["k"].as_s.should eq(value)
      end
    end
  end

  describe ".toml_to_yaml_any" do
    it "carries scalars across unchanged" do
      parsed = TOML.parse(%(s = "x"\ni = 3\nf = 1.5\nb = true))
      Hwaro::Utils::FrontmatterWriter.toml_to_yaml_any(parsed["s"]).as_s.should eq("x")
      Hwaro::Utils::FrontmatterWriter.toml_to_yaml_any(parsed["i"]).as_i.should eq(3)
      Hwaro::Utils::FrontmatterWriter.toml_to_yaml_any(parsed["f"]).as_f.should eq(1.5)
      Hwaro::Utils::FrontmatterWriter.toml_to_yaml_any(parsed["b"]).as_bool.should be_true
    end

    it "converts a TOML date leaf into a frontmatter date string" do
      parsed = TOML.parse("date = 2026-05-20T08:30:15Z")
      Hwaro::Utils::FrontmatterWriter.toml_to_yaml_any(parsed["date"]).as_s.should eq("2026-05-20T08:30:15Z")
    end

    it "converts an array recursively" do
      parsed = TOML.parse(%(tags = ["a", "b"]))
      result = Hwaro::Utils::FrontmatterWriter.toml_to_yaml_any(parsed["tags"])
      result.as_a.map(&.as_s).should eq(["a", "b"])
    end

    it "converts a nested table recursively and preserves key order" do
      parsed = TOML.parse(%([extra]\nz = "last"\na = "first"))
      result = Hwaro::Utils::FrontmatterWriter.toml_to_yaml_any(parsed["extra"])
      result.as_h.keys.map(&.as_s).should eq(["z", "a"])
      result["a"].as_s.should eq("first")
    end
  end

  describe Hwaro::Utils::FrontmatterWriter::TomlBuilder do
    it "returns an empty string for a non-mapping root" do
      Hwaro::Utils::FrontmatterWriter::TomlBuilder.new.build(YAML::Any.new("scalar")).should eq("")
    end

    it "emits scalars with their TOML types intact" do
      doc = toml_build({
        "title" => yaml_any("Hello"),
        "draft" => yaml_any(false),
        "count" => yaml_any(3),
      })
      parsed = TOML.parse(doc)
      parsed["title"].should eq("Hello")
      parsed["draft"].raw.should be_false
      parsed["count"].should eq(3)
    end

    it "preserves source key order among scalars" do
      doc = toml_build({"z" => yaml_any("1"), "a" => yaml_any("2"), "m" => yaml_any("3")})
      doc.lines.map(&.split(" =").first).should eq(["z", "a", "m"])
    end

    # Ordering is not cosmetic: a scalar emitted after a `[table]` header would
    # be swallowed into that table.
    it "emits every scalar before the first table header" do
      doc = toml_build({
        "extra" => YAML.parse({"k" => "v"}.to_yaml),
        "title" => yaml_any("Hello"),
      })
      doc.index!("title =").should be < doc.index!("[extra]")
      TOML.parse(doc)["title"].should eq("Hello")
    end

    it "quotes a key that is not a bare TOML key" do
      doc = toml_build({"my key" => yaml_any("v")})
      doc.should contain(%q("my key" = "v"))
      TOML.parse(doc)["my key"].should eq("v")
    end

    it "emits a nested table as a [table] section" do
      doc = toml_build({"extra" => YAML.parse({"a" => "1", "b" => "2"}.to_yaml)})
      TOML.parse(doc)["extra"].as_h.should eq({"a" => "1", "b" => "2"})
    end

    it "emits a deeply nested table with a dotted header" do
      doc = toml_build({"a" => YAML.parse({"b" => {"c" => "deep"}}.to_yaml)})
      doc.should contain("[a.b]")
      TOML.parse(doc)["a"].as_h["b"].as_h["c"].should eq("deep")
    end

    # An empty table has no values to force a header doc; dropping the key
    # entirely would silently lose it.
    it "keeps an empty table as a bare header" do
      doc = toml_build({"extra" => YAML.parse(({} of String => String).to_yaml)})
      doc.should contain("[extra]")
      TOML.parse(doc)["extra"].as_h.should be_empty
    end

    it "emits an array of tables as [[section]] entries" do
      doc = toml_build({"authors" => YAML.parse([{"name" => "a"}, {"name" => "b"}].to_yaml)})
      doc.scan(/\[\[authors\]\]/).size.should eq(2)
      TOML.parse(doc)["authors"].as_a.map(&.as_h["name"]).should eq(["a", "b"])
    end

    it "escapes strings through the shared TOML escaper" do
      doc = toml_build({"title" => yaml_any(%(say "hi"\nbye))})
      TOML.parse(doc)["title"].should eq(%(say "hi"\nbye))
    end

    it "emits nil as an empty string, since TOML has no null" do
      doc = toml_build({"x" => YAML.parse("---\n")})
      TOML.parse(doc)["x"].should eq("")
    end

    # Crystal spells these "Infinity"/"NaN", which TOML cannot reparse.
    it "spells non-finite floats the way TOML does" do
      doc = toml_build({
        "pos" => YAML::Any.new(Float64::INFINITY),
        "neg" => YAML::Any.new(-Float64::INFINITY),
        "nan" => YAML::Any.new(Float64::NAN),
      })
      doc.should contain("pos = inf")
      doc.should contain("neg = -inf")
      doc.should contain("nan = nan")
    end

    it "emits a homogeneous array unchanged" do
      doc = toml_build({"tags" => yaml_any(["a", "b"])})
      TOML.parse(doc)["tags"].as_a.should eq(["a", "b"])
    end

    it "emits an empty array" do
      doc = toml_build({"tags" => yaml_any([] of String)})
      TOML.parse(doc)["tags"].as_a.should be_empty
    end

    # toml.cr refuses arrays that mix type families.
    it "promotes an int/float mix to floats so the array stays homogeneous" do
      doc = toml_build({"nums" => YAML::Any.new([YAML::Any.new(1_i64), YAML::Any.new(2.5)])})
      TOML.parse(doc)["nums"].as_a.map(&.raw).should eq([1.0, 2.5])
    end

    it "coerces any other scalar mix to strings" do
      doc = toml_build({"mixed" => YAML::Any.new([YAML::Any.new(1_i64), YAML::Any.new("two")])})
      TOML.parse(doc)["mixed"].as_a.should eq(["1", "two"])
    end

    it "coerces a bool/string mix to strings" do
      doc = toml_build({"mixed" => YAML::Any.new([YAML::Any.new(true), YAML::Any.new("x")])})
      TOML.parse(doc)["mixed"].as_a.should eq(["true", "x"])
    end

    # A hash reached from inside an array cannot become a [table] section, so
    # it is emitted as an inline table — valid only while the array stays
    # homogeneous.
    it "emits a hash inside an all-table array as an inline table" do
      value = YAML::Any.new([
        YAML.parse({"k" => "v"}.to_yaml),
        YAML.parse({"k" => "w"}.to_yaml),
      ])
      doc = toml_build({"items" => value})
      TOML.parse(doc)["items"].as_a.map(&.as_h["k"]).should eq(["v", "w"])
    end

    # Regression: `["plain", {k = "v"}]` is exactly the mixed array toml.cr
    # refuses, so `tool convert to-toml` used to write a file that the next
    # `hwaro build` rejected with "cannot mix types in array".
    it "keeps a scalar/table mix parseable by stringifying the table" do
      value = YAML::Any.new([
        YAML::Any.new("plain"),
        YAML.parse({"k" => "v"}.to_yaml),
      ])
      doc = toml_build({"items" => value})
      TOML.parse(doc)["items"].as_a.should eq(["plain", %q({"k":"v"})])
    end

    it "keeps a scalar/array mix parseable by stringifying the array" do
      value = YAML::Any.new([
        YAML::Any.new("plain"),
        YAML::Any.new([YAML::Any.new("a"), YAML::Any.new("b")]),
      ])
      doc = toml_build({"items" => value})
      TOML.parse(doc)["items"].as_a.should eq(["plain", %q(["a","b"])])
    end

    it "never emits an array TOML cannot reparse, whatever the mix" do
      mixes = [
        [YAML::Any.new("s"), YAML::Any.new(1_i64)],
        [YAML::Any.new(true), YAML.parse({"k" => "v"}.to_yaml)],
        [YAML::Any.new(1_i64), YAML::Any.new([YAML::Any.new("a")])],
        [YAML::Any.new("s"), YAML::Any.new(2.5), YAML.parse({"k" => "v"}.to_yaml)],
      ]
      mixes.each do |items|
        doc = toml_build({"items" => YAML::Any.new(items)})
        TOML.parse(doc)["items"].as_a.size.should eq(items.size)
      end
    end

    it "produces parseable output for a realistic frontmatter tree" do
      doc = toml_build({
        "title"   => yaml_any("My Post"),
        "date"    => yaml_any("2026-05-20"),
        "draft"   => yaml_any(false),
        "tags"    => yaml_any(["crystal", "ssg"]),
        "extra"   => YAML.parse({"cover" => "a.png"}.to_yaml),
        "authors" => YAML.parse([{"name" => "hahwul"}].to_yaml),
      })
      parsed = TOML.parse(doc)
      parsed["title"].should eq("My Post")
      parsed["tags"].as_a.should eq(["crystal", "ssg"])
      parsed["extra"].as_h["cover"].should eq("a.png")
      parsed["authors"].as_a.first.as_h["name"].should eq("hahwul")
    end

    it "accepts a string-keyed field map as well as a YAML::Any root" do
      fields = {"title" => yaml_any("X")}
      Hwaro::Utils::FrontmatterWriter::TomlBuilder.new.build(fields)
        .should eq(%(title = "X"\n))
    end
  end
end
