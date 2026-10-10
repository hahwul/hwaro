require "../../spec_helper"
require "../../support/build_helper"
require "../../../src/hwaro"

# Regression coverage for the crash-hardening pass: inputs that used to abort a
# command with an UNCLASSIFIED exception (a bare stdlib ArgumentError /
# OverflowError surfacing as `Error: <stdlib message>` — no code, no file, no
# hint) now produce a classified error or a defined fallback.

# `File.tempfile`'s block form closes the file but does NOT delete it, and the
# deep-dotted-key examples below write multi-megabyte configs — so clean up
# explicitly rather than leaving a pile of them in the system temp dir.
# As written in a config file: a well-formed TOML escape that decodes to a NUL.
TOML_NUL = "x\\u0000z"
# The decoded string a Crystal caller would hold.
RAW_NUL = "x#{Char::ZERO}z"

describe "crash hardening" do
  # ---------------------------------------------------------------------------
  # NUL bytes in config strings.
  #
  # The escape survives TOML parsing, so the NUL reached every consumer of the
  # value. Anything that then built a Path from it raised
  # `ArgumentError: String contains null byte` out of stdlib's
  # check_no_null_byte — reported as the unclassified
  # `Error: String contains null byte`, naming neither the key nor the file.
  # `validate_output_filename!` could not catch it either: its own
  # `File.basename(value)` operand raised before the NUL test it guarded ran.
  # ---------------------------------------------------------------------------
  describe "Config.load with a NUL byte in a string value" do
    {
      "build.output_dir"         => %([build]\noutput_dir = "#{TOML_NUL}"\n),
      "sitemap.filename"         => %([sitemap]\nenabled = true\nfilename = "#{TOML_NUL}"\n),
      "robots.filename"          => %([robots]\nfilename = "#{TOML_NUL}"\n),
      "llms.filename"            => %([llms]\nfilename = "#{TOML_NUL}"\n),
      "llms.full_filename"       => %([llms]\nfull_filename = "#{TOML_NUL}"\n),
      "feeds.filename"           => %([feeds]\nfilename = "#{TOML_NUL}"\n),
      "search.filename"          => %([search]\nfilename = "#{TOML_NUL}"\n),
      "og.auto_image.output_dir" => %([og.auto_image]\noutput_dir = "#{TOML_NUL}"\n),
    }.each do |key, toml|
      it "raises a classified config error naming #{key}" do
        err = expect_raises(Hwaro::HwaroError) { load_config(toml) }
        err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
        (err.message || "").should contain(key)
        (err.message || "").should contain("NUL")
      end
    end

    it "reports a NUL inside an array element with its index" do
      err = expect_raises(Hwaro::HwaroError) do
        load_config(%([sitemap]\nenabled = true\nexclude = ["ok", "#{TOML_NUL}"]\n))
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      (err.message || "").should contain("sitemap.exclude[1]")
    end

    it "reports a NUL in a plain (non-path) string too" do
      err = expect_raises(Hwaro::HwaroError) { load_config(%(title = "#{TOML_NUL}"\n)) }
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      (err.message || "").should contain("title")
    end

    # `[a.b.c…]` builds one nested table per dotted segment and never enters
    # `parse_value`, so ext/toml_nesting_limit_fix.cr's cap does not apply: the
    # parser accepts a 50k-segment header. A RECURSIVE scan of the result
    # overflowed the stack — unrescuable, and on a config the section loaders
    # never descend into. The scan is iterative for exactly this reason.
    it "scans a pathologically deep dotted-key table without overflowing" do
      deep = Array.new(20_000) { |i| "k#{i}" }.join('.')
      config = load_config("[#{deep}]\nx = 1\n")
      config.title.should_not be_nil
    end

    it "still finds a NUL buried in a pathologically deep table" do
      deep = Array.new(20_000) { |i| "k#{i}" }.join('.')
      err = expect_raises(Hwaro::HwaroError) { load_config(%([#{deep}]\nx = "#{TOML_NUL}"\n)) }
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      (err.message || "").should contain("NUL")
    end

    # A quoted TOML key carries the escape exactly as a value does, and both
    # `[languages.<code>]` and `[menus.<name>]` keys are joined into output
    # paths downstream.
    it "rejects a NUL in a quoted table key" do
      err = expect_raises(Hwaro::HwaroError) do
        load_config(%([languages."e#{TOML_NUL}n"]\nlanguage_name = "En"\n))
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      (err.message || "").should contain("NUL")
    end

    it "rejects a NUL in a top-level key" do
      err = expect_raises(Hwaro::HwaroError) { load_config(%("a#{TOML_NUL}b" = 1\n)) }
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
    end

    it "rejects a NUL in an inline-table key" do
      err = expect_raises(Hwaro::HwaroError) do
        load_config(%([markdown]\nx = { "k#{TOML_NUL}y" = 1 }\n))
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
    end

    it "leaves NUL-free configs untouched" do
      config = load_config(%(title = "ok"\n[sitemap]\nenabled = true\nfilename = "sitemap.xml"\n))
      config.title.should eq("ok")
      config.sitemap.filename.should eq("sitemap.xml")
    end
  end

  # ---------------------------------------------------------------------------
  # OutputGuard: a SAFETY predicate must answer, never raise. File.expand_path
  # builds a Path, so a NUL made both entry points abort the build instead of
  # reporting "not inside the output directory".
  # ---------------------------------------------------------------------------
  describe Hwaro::Utils::OutputGuard do
    it "returns nil for an output path containing a NUL byte" do
      Hwaro::Utils::OutputGuard.safe_output_path("public/#{RAW_NUL}.html", "public").should be_nil
    end

    it "returns nil when the output DIRECTORY contains a NUL byte" do
      Hwaro::Utils::OutputGuard.safe_output_path("public/a.html", RAW_NUL).should be_nil
    end

    it "answers false instead of raising for a NUL path" do
      Hwaro::Utils::OutputGuard.within_output_dir?("public/#{RAW_NUL}.html", "public").should be_false
      Hwaro::Utils::OutputGuard.within_output_dir?("public/a.html", RAW_NUL).should be_false
    end
  end

  # ---------------------------------------------------------------------------
  # TextUtils formatting helpers: both raised on out-of-range integer inputs.
  # truncate_error runs while REPORTING another failure, so a raise there
  # replaces a real diagnostic with a stdlib message.
  # ---------------------------------------------------------------------------
  describe Hwaro::Utils::TextUtils do
    it "clamps a negative truncate_error budget instead of raising" do
      result = Hwaro::Utils::TextUtils.truncate_error("template failed", -1)
      result.should contain("truncated")
      result.should contain("15 characters")
    end

    it "keeps a zero budget usable" do
      Hwaro::Utils::TextUtils.truncate_error("abc", 0).should start_with("…")
    end

    it "does not overflow pad_display at the Int32 extremes" do
      Hwaro::Utils::TextUtils.pad_display("ab", Int32::MIN).should eq("ab")
      Hwaro::Utils::TextUtils.pad_display("ab", Int32::MAX).size.should be <= 10_002 # 2 + MAX_PAD_COLUMNS
    end

    it "still pads normally" do
      Hwaro::Utils::TextUtils.pad_display("ab", 5).should eq("ab   ")
      Hwaro::Utils::TextUtils.pad_display("abcdef", 3).should eq("abcdef")
    end
  end

  # ---------------------------------------------------------------------------
  # Exponential backtracking. Each regex below had two quantifiers that could
  # split the same characters many ways, so a failing match on ~100 bytes ran
  # into PCRE2's match limit and raised `Regex::Error` — which aborted the
  # page, or with backlinks on the whole build as a bare `Error: Regex match
  # error: match limit exceeded`. Possessive quantifiers remove the choice.
  # ---------------------------------------------------------------------------
  describe "regexes over author content" do
    url_args = "url=https://example.com/s?" + (1..20).map { |i| "k#{i}=#{i}" }.join("&") + "&u=a%20b"

    it "fails a shortcode tag with many k=v pairs and a stray % without raising" do
      tag = "{% embed #{url_args} %}"
      Hwaro::Core::Build::ShortcodeProcessor::BLOCK_OPEN_RE.match(tag).should be_nil
    end

    it "fails a tag with many quoted args and a stray word without raising" do
      tag = "{% embed " + (1..12).map { |i| %(k#{i}="v") }.join(" ") + " stray %}"
      Hwaro::Core::Build::ShortcodeProcessor::BLOCK_OPEN_RE.match(tag).should be_nil
    end

    it "still opens a block whose quoted value is followed by more text" do
      # An apostrophe typo or a suffix after the closing quote: the value is
      # read unquoted, as before, so the block still opens.
      [%({% note title='Don't' %}), %({% note title="v1"beta %}), %({% note a="x"b=2 %})].each do |tag|
        Hwaro::Core::Build::ShortcodeProcessor::BLOCK_OPEN_RE.match!(tag)[1].should eq("note")
      end
    end

    it "still matches ordinary block shortcode tags" do
      md = Hwaro::Core::Build::ShortcodeProcessor::BLOCK_OPEN_RE.match!(%({% alert type="warning", title='a b' n=3 %}))
      md[1].should eq("alert")
      md[3].should eq(%(type="warning", title='a b' n=3 ))
      Hwaro::Core::Build::ShortcodeProcessor::BLOCK_OPEN_RE.match!(%({% note(kind="x") %}))[2].should eq(%(kind="x"))
    end

    it "fails deep blockquote prefixes without raising" do
      Hwaro::Content::Processors::MarkdownExtensions::HEADING_ID_RE.match("> " * 25 + "# Title {#} }").should be_nil
      Hwaro::Content::Processors::MarkdownExtensions::HEADING_ATTR_RE.match("> " * 25 + "# Title {} }").should be_nil
      Hwaro::Content::Processors::MarkdownExtensions::TASK_LIST_RE.match(">  " * 40 + "- x [ ]").should be_nil
      Hwaro::Content::Processors::Wikilinks::STANDALONE_LINE_RE.match(">  " * 25 + "x").should be_nil
    end

    it "still matches quoted headings, task items and standalone lines" do
      md = Hwaro::Content::Processors::MarkdownExtensions::HEADING_ID_RE.match!(">  > ## Title {#tid}")
      md[1].should eq(">  > ")
      md[4].should eq("tid")
      Hwaro::Content::Processors::MarkdownExtensions::HEADING_ATTR_RE.match!("> # T {.c}")[4].should eq(".c")
      Hwaro::Content::Processors::MarkdownExtensions::TASK_LIST_RE.match!("> >  - [x] done")[1].should eq("> >  - ")
      Hwaro::Content::Processors::Wikilinks::STANDALONE_LINE_RE.matches?(">    # h").should be_true
      Hwaro::Content::Processors::Wikilinks::STANDALONE_LINE_RE.matches?("> > ---\n").should be_true
    end
  end

  # ---------------------------------------------------------------------------
  # Template recursion. A macro without a base case and a `{% from %}` import
  # cycle both recursed until the native stack was gone — an unrescuable
  # `Stack overflow` that also killed `hwaro serve`.
  # ---------------------------------------------------------------------------
  describe "template recursion" do
    content = {"index.md" => "---\ntitle: Home\n---\nhello"}

    it "reports unbounded macro recursion as a template error" do
      err = expect_raises(Hwaro::HwaroError) do
        build_site(BASIC_CONFIG, content_files: content, template_files: {
          "index.html" => %({% macro f(n) %}{{ f(n + 1) }}{% endmacro %}{{ f(1) }}),
        }) { }
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_TEMPLATE)
      err.message.not_nil!.should contain("Template recursion too deep")
    end

    it "reports a {% from %} import cycle as a template error" do
      err = expect_raises(Hwaro::HwaroError) do
        build_site(BASIC_CONFIG, content_files: content, template_files: {
          "index.html" => %({% from "b.html" import m %}x),
          "b.html"     => %({% from "index.html" import m %}{% macro m() %}{% endmacro %}),
        }) { }
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_TEMPLATE)
      err.message.not_nil!.should contain("Template recursion too deep")
    end

    it "stops recursion whose levels are heavy before the stack runs out" do
      # Each level nests ten for/if tags: far more stack per level than a
      # bare call, which a fixed level count did not account for.
      open_tags = (1..10).map { |i| "{% for a#{i} in [1] %}{% if a#{i} %}" }.join
      close_tags = "{% endif %}{% endfor %}" * 10
      err = expect_raises(Hwaro::HwaroError) do
        build_site(BASIC_CONFIG, content_files: content, template_files: {
          "index.html" => %({% macro f(n) %}#{open_tags}{{ f(n + 1) | trim }}#{close_tags}{% endmacro %}{{ f(1) }}),
        }) { }
      end
      err.message.not_nil!.should contain("Template recursion too deep")
    end

    it "still renders deep terminating recursion and repeated macro calls" do
      build_site(BASIC_CONFIG, content_files: content, template_files: {
        "index.html" => %({% macro f(n) %}{% if n < 300 %}{{ f(n + 1) }}{% else %}DEPTH{{ n }}{% endif %}{% endmacro %}) +
                        %({% for i in range(300) %}{{ f(299) }}{% endfor %}{{ f(1) }}),
      }) do
        html = File.read("public/index.html")
        html.should contain("DEPTH300")
        html.scan("DEPTH300").size.should eq(301)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Unreadable config / archetype: `File.exists?` admitted a directory, and
  # the raw File::Error reached the runner as a bare "Error: ..." line.
  # ---------------------------------------------------------------------------
  it "classifies a config.toml that is a directory" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.toml")
      Dir.mkdir(path)
      err = expect_raises(Hwaro::HwaroError) { Hwaro::Models::Config.load(path) }
      err.code.should eq(Hwaro::Errors::HWARO_E_CONFIG)
      err.message.not_nil!.should contain("config.toml")
    end
  end

  it "skips an archetype path that is a directory instead of reading it" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("archetypes/posts.md")
        File.write("archetypes/default.md", "+++\ntitle = \"{{ title }}\"\n+++\nFROM-DEFAULT\n")
        Hwaro::Services::Creator.new.run(Hwaro::Config::Options::NewOptions.new(path: "posts/zz.md"))
        File.read("content/posts/zz.md").should contain("FROM-DEFAULT")
      end
    end
  end

  it "classifies an unreadable archetype" do
    posix_only!("chmod-based permissions")
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("archetypes")
        File.write("archetypes/default.md", "x")
        File.chmod("archetypes/default.md", 0o000)
        next if (File.read("archetypes/default.md") rescue nil) # running as root
        err = expect_raises(Hwaro::HwaroError) do
          Hwaro::Services::Creator.new.run(Hwaro::Config::Options::NewOptions.new(path: "hello.md"))
        end
        err.code.should eq(Hwaro::Errors::HWARO_E_IO)
        err.message.not_nil!.should contain("archetypes/default.md")
      end
    end
  end

  it "keeps the HTML minifier linear on many unterminated comments" do
    html = "<div>\n" + "<!--\n" * 40_000
    elapsed = Time.measure { Hwaro::Utils::HtmlMinifier.minify(html) }
    elapsed.should be < 5.seconds # was ~30s
  end

  # ---------------------------------------------------------------------------
  # Non-regular files. A FIFO matching a walk's glob blocked `File.read`
  # forever; a unix socket stands in for it here (see edge_cases_spec) — the
  # same non-regular-file guard, but `open(2)` fails fast instead of hanging.
  # ---------------------------------------------------------------------------
  it "skips non-regular files under data/ and i18n/ in a --cache build" do
    posix_only!("unix sockets")
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        {"content", "templates", "data", "i18n"}.each { |d| FileUtils.mkdir_p(d) }
        File.write("content/index.md", "---\ntitle: Home\n---\nHOME-BODY")
        File.write("templates/index.html", "{{ content }}")
        File.write("data/ok.json", %({"a": 1}))
        # `en.toml`: the default language's file is also read by the
        # translation loader, not only by the --cache digest walk.
        sockets = {UNIXServer.new("data/zz.json"), UNIXServer.new("i18n/en.toml")}
        begin
          log = with_captured_log do
            builder = Hwaro::Core::Build::Builder.new
            Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
            builder.run(Hwaro::Config::Options::BuildOptions.new(cache: true, parallel: false, highlight: false))
          end
          File.read("public/index.html").should contain("HOME-BODY")
          log.should_not contain("Failed to parse i18n file")
        ensure
          sockets.each(&.close)
        end
      end
    end
  end

  it "skips a non-regular Markdown entry on export" do
    posix_only!("unix sockets")
    Dir.mktmpdir do |dir|
      content_dir = File.join(dir, "content")
      FileUtils.mkdir_p(content_dir)
      File.write(File.join(content_dir, "a.md"), "---\ntitle: A\n---\nbody")
      server = UNIXServer.new(File.join(content_dir, "s.md"))
      begin
        result = Hwaro::Services::Exporters::HugoExporter.new.run(
          Hwaro::Config::Options::ExportOptions.new(target_type: "hugo", content_dir: content_dir, output_dir: File.join(dir, "out")))
        result.success.should be_true
        result.exported_count.should eq(1)
      ensure
        server.close
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Dates. `Time::Location::InvalidTimezoneOffsetError` (an offset past ±24h)
  # is a Time::Error, which none of the date parsers rescued; and a Time whose
  # UTC instant is before year 1 raised from the feed generator's `to_utc`.
  # ---------------------------------------------------------------------------
  it "treats a date with an impossible UTC offset as unparseable" do
    Hwaro::Utils::DateUtils.parse_content_date("2024-01-01T00:00:00+99:00").should be_nil
    Hwaro::Utils::DateUtils.parse_content_date("2024-01-01 00:00:00 +9900").should be_nil
    # The lenient (importer) parser may keep the date and drop the offset;
    # it must just not raise.
    Hwaro::Utils::DateUtils.parse_lenient("2024-01-01T00:00:00+99:00")
    Hwaro::Utils::DateUtils.parse_import("2024-01-01T00:00:00+99:00")
  end

  it "builds the feed for a page whose date falls before year 1 in UTC" do
    build_site(BASIC_CONFIG + "\n[feeds]\nenabled = true\n", content_files: {
      "index.md" => "---\ntitle: Home\n---\nhome",
      "old.md"   => "+++\ntitle = \"Old\"\ndate = 0001-01-01T00:00:00+23:59\n+++\nOLD-BODY",
      "old2.md"  => "+++\ntitle = \"Old2\"\ndate = \"0001-01-01T00:00:00+23:59\"\n+++\nOLD2-BODY",
    }, template_files: {"page.html" => "{{ content }}", "index.html" => "{{ content }}"}) do
      File.read("public/old/index.html").should contain("OLD-BODY")
      File.read("public/rss.xml").should contain("01 Jan 0001")
    end
  end

  it "builds FAQ / HowTo JSON-LD from parallel arrays of unequal length" do
    page = Hwaro::Models::Page.new("faq.md")
    page.url = "/faq/"
    page.extra["faq_questions"] = ["q1", "q2"].as(Hwaro::Models::ExtraValue)
    page.extra["faq_answers"] = ["a1"].as(Hwaro::Models::ExtraValue)
    page.extra["howto_names"] = ["n1", "n2"].as(Hwaro::Models::ExtraValue)
    page.extra["howto_texts"] = ["t1"].as(Hwaro::Models::ExtraValue)
    config = Hwaro::Models::Config.new
    faq = Hwaro::Content::Seo::JsonLd.faq_page(page, config)
    faq.should contain("q1")
    faq.should_not contain("q2")
    Hwaro::Content::Seo::JsonLd.how_to(page, config).should contain("n1")
  end

  # ---------------------------------------------------------------------------
  # Forged placeholders. The restore passes indexed their stash with digits
  # read back from the text, which author content can forge: an index past
  # the end raised IndexError, a 20-digit run made `to_i` raise.
  # ---------------------------------------------------------------------------
  it "leaves a forged code-span placeholder in a transcluded heading alone" do
    {"&#xE000;9&#xE001;", "&#xE000;99999999999999999999&#xE001;"}.each do |forged|
      Hwaro::Content::Processors::Includes.heading_section("# Weird #{forged}\n\nw\n\n# Setup\n\nSETUP\n", "Setup")
        .not_nil!.should contain("SETUP")
    end
  end

  it "leaves an over-long forged placeholder token in the body alone" do
    build_site(BASIC_CONFIG, content_files: {
      "index.md" => "---\ntitle: Home\n---\n~~a~~ [x](/y) \0LD99999999999999999999\0 \0HT99999999999999999999\0 MARK",
    }, template_files: {"index.html" => "{{ content }}"}) do
      File.read("public/index.html").should contain("MARK")
    end
  end

  it "ignores a slug or path containing a NUL byte" do
    build_site(BASIC_CONFIG + "\n[amp]\nenabled = true\n", content_files: {
      "index.md" => "---\ntitle: Home\n---\nhome",
      "a.md"     => "+++\ntitle = \"A\"\nslug = \"a\\u0000b\"\n+++\nA-BODY",
      "b.md"     => "+++\ntitle = \"B\"\npath = \"b\\u0000c\"\n+++\nB-BODY",
    }, template_files: {"page.html" => "{{ content }}", "index.html" => "{{ content }}"}) do
      File.read("public/a/index.html").should contain("A-BODY")
      File.read("public/b/index.html").should contain("B-BODY")
    end
  end

  # ---------------------------------------------------------------------------
  # Content-controlled regex sources: PCRE2 refuses to compile a pattern
  # past ~10k characters ("regular expression is too large").
  # ---------------------------------------------------------------------------
  it "reports a strict-schema unknown key that is too long to locate by line" do
    config = BASIC_CONFIG + %(\n[[content.schema]]\nsections = ["**"]\nstrict = true\n[content.schema.fields.title]\ntype = "string"\n)
    err = expect_raises(Hwaro::HwaroError) do
      build_site(config, content_files: {"p.md" => "+++\ntitle = \"x\"\n#{"k" * 12_000} = 1\n+++\nbody"}) { }
    end
    err.code.should_not eq(Hwaro::Errors::HWARO_E_INTERNAL)
  end

  it "caps include fan-out per page instead of expanding it exponentially" do
    # Ten includes per file, five deep: 10^5 splices from six tiny files.
    files = {} of String => String
    5.times { |i| files["inc/n#{i}.md"] = %({{ include_md(path="static/inc/n#{i + 1}.md") }}\n) * 10 }
    files["inc/n5.md"] = "x\n"
    # No timing assertion: reaching the cap takes ~1s on macOS but ~15s on
    # Windows CI. Without the cap this expands all 10^5 splices and returns
    # normally, so the raise alone proves it.
    err = expect_raises(Hwaro::HwaroError) do
      build_site(BASIC_CONFIG, static_files: files, content_files: {
        "index.md" => %(---\ntitle: Home\n---\n{{ include_md(path="static/inc/n0.md") }}\n),
      }) { }
    end
    err.message.not_nil!.should contain("include limit")
  end

  it "scrubs invalid UTF-8 out of data strings" do
    value = Hwaro::Utils::CrinjaUtils.parse_data_string(%([{"t": "T\xff"}]), "json").not_nil!
    value[0]["t"].to_s.should eq("T\u{FFFD}")
  end
end
