require "../spec_helper"
require "../../src/core/build/builder"

# Edge-case coverage for ShortcodeProcessor that complements
# `builder_shortcode_spec.cr`. Focuses on malformed input, error paths,
# and uncommon nesting patterns called out in issue #328.
module Hwaro::Core::Build
  class Builder
    def test_sc_process(content, templates = {} of String => String, context = {} of String => Crinja::Value)
      process_shortcodes_jinja(content, templates, context)
    end

    def test_sc_process_with_results(content, templates, context, results)
      process_shortcodes_jinja(content, templates, context, results)
    end

    def test_sc_render_jinja(template, args, context = {} of String => Crinja::Value)
      render_shortcode_jinja(template, args, context)
    end

    def test_sc_parse_args(s)
      parse_shortcode_args_jinja(s)
    end
  end
end

describe Hwaro::Core::Build::ShortcodeProcessor do
  describe "block shortcodes with arguments" do
    it "passes named args from a block shortcode opening tag" do
      builder = Hwaro::Core::Build::Builder.new
      templates = {
        "shortcodes/alert" => %(<div class="{{ kind }}">{{ body }}</div>),
      }
      result = builder.test_sc_process(
        %({% alert(kind="warning") %}careful{% end %}),
        templates,
      )
      result.should contain(%(<div class="warning">))
      result.should contain("careful")
    end

    it "passes positional args from a block shortcode opening tag" do
      builder = Hwaro::Core::Build::Builder.new
      templates = {
        "shortcodes/wrap" => %(<div class="{{ _0 }}">{{ body }}</div>),
      }
      result = builder.test_sc_process(
        %({% wrap("box") %}content{% end %}),
        templates,
      )
      result.should contain(%(<div class="box">))
    end
  end

  describe "unknown shortcodes" do
    it "leaves direct-call references untouched when no template matches" do
      builder = Hwaro::Core::Build::Builder.new
      content = %(text {{ unknown(arg="x") }} more)
      result = builder.test_sc_process(content, {} of String => String)
      result.should eq(content)
    end

    it "leaves explicit shortcode() calls untouched when template missing" do
      builder = Hwaro::Core::Build::Builder.new
      content = %({{ shortcode("missing", arg="x") }})
      result = builder.test_sc_process(content, {} of String => String)
      result.should eq(content)
    end

    it "leaves block shortcodes untouched when template missing" do
      builder = Hwaro::Core::Build::Builder.new
      content = %({% missing %}body{% end %})
      result = builder.test_sc_process(content, {} of String => String)
      # Block path returns the original block as fallback, byte-for-byte
      result.should eq(content)
    end

    it "warns when a direct-call shortcode name is not a registered template or Crinja function" do
      builder = Hwaro::Core::Build::Builder.new
      sink = IO::Memory.new
      previous_io = Hwaro::Logger.io
      Hwaro::Logger.io = sink
      begin
        builder.test_sc_process(%(text {{ typo_sc(arg="x") }} more), {} of String => String)
      ensure
        Hwaro::Logger.io = previous_io
      end
      sink.to_s.should contain("Shortcode template 'shortcodes/typo_sc' not found.")
    end

    it "does not warn when a direct call matches a registered Crinja function name" do
      # `env`, `asset`, `url_for`, `get_url`, `resize_image`, … are
      # registered on the shared Crinja env by the template processor.
      # Direct-call syntax in content ({{ env(\"X\") }}) is a legitimate
      # template-function reference, not a typo'd shortcode, so the
      # shortcode processor must silent-pass-through.
      builder = Hwaro::Core::Build::Builder.new
      sink = IO::Memory.new
      previous_io = Hwaro::Logger.io
      Hwaro::Logger.io = sink
      begin
        builder.test_sc_process(%({{ env("FOO") }} {{ asset(name="x.css") }}), {} of String => String)
      ensure
        Hwaro::Logger.io = previous_io
      end
      sink.to_s.should_not contain("Shortcode template")
    end

    it "dedupes missing-template warnings across multiple invocations" do
      builder = Hwaro::Core::Build::Builder.new
      sink = IO::Memory.new
      previous_io = Hwaro::Logger.io
      Hwaro::Logger.io = sink
      begin
        # Same missing shortcode used three times, in two syntaxes.
        builder.test_sc_process(
          %({{ missing_sc(a="1") }} {{ missing_sc(a="2") }} {% missing_sc %}b{% end %}),
          {} of String => String,
        )
      ensure
        Hwaro::Logger.io = previous_io
      end
      # Exactly one warning line per unique missing template key.
      output = sink.to_s
      output.scan("Shortcode template 'shortcodes/missing_sc' not found.").size.should eq(1)
    end
  end

  describe "malformed shortcodes" do
    it "returns empty string when the shortcode template has a Crinja error" do
      builder = Hwaro::Core::Build::Builder.new
      # Unbalanced/invalid Jinja syntax in the template
      result = builder.test_sc_render_jinja(
        "{% if %}",
        {} of String => String,
        {} of String => Crinja::Value,
      )
      result.should eq("")
    end

    it "treats a stray {% end %} preceding shortcodes as literal text" do
      builder = Hwaro::Core::Build::Builder.new
      templates = {"shortcodes/note" => "<span>{{ body }}</span>"}
      result = builder.test_sc_process(
        "{% end %} normal text {% note %}body{% end %}",
        templates,
      )
      result.should contain("{% end %}")
      result.should contain("<span>body</span>")
    end

    it "handles unclosed code fence — content after open fence is left untouched" do
      builder = Hwaro::Core::Build::Builder.new
      templates = {"shortcodes/note" => "<span>{{ body }}</span>"}
      content = "before\n```\n{% note %}skipped{% end %}\nno close fence"
      result = builder.test_sc_process(content, templates)
      # The shortcode inside the never-closed fence stays raw
      result.should contain("{% note %}skipped{% end %}")
      result.should_not contain("<span>")
    end
  end

  describe "code fences" do
    it "leaves shortcodes inside indented backtick fences untouched" do
      builder = Hwaro::Core::Build::Builder.new
      templates = {"shortcodes/note" => "<span>{{ body }}</span>"}
      content = "  ```\n  {% note %}body{% end %}\n  ```"
      result = builder.test_sc_process(content, templates)
      result.should contain("{% note %}body{% end %}")
      result.should_not contain("<span>")
    end

    it "processes shortcodes between adjacent fences" do
      builder = Hwaro::Core::Build::Builder.new
      templates = {"shortcodes/note" => "<span>{{ body }}</span>"}
      content = "```\nfenced1\n```\n{% note %}live{% end %}\n```\nfenced2\n```"
      result = builder.test_sc_process(content, templates)
      result.should contain("<span>live</span>")
      result.should contain("fenced1")
      result.should contain("fenced2")
    end
  end

  describe "nested shortcodes" do
    it "renders nested explicit calls inside a block body" do
      builder = Hwaro::Core::Build::Builder.new
      templates = {
        "shortcodes/box"   => %(<div class="box">{{ body }}</div>),
        "shortcodes/badge" => %(<i>{{ _0 }}</i>),
      }
      content = %({% box %}label: {{ badge("v1") }}{% end %})
      result = builder.test_sc_process(content, templates)
      result.should contain("<div class=\"box\">")
      result.should contain("<i>v1</i>")
    end

    it "allows mixed block/inline nesting in a single body" do
      builder = Hwaro::Core::Build::Builder.new
      templates = {
        "shortcodes/box"   => %(<div>{{ body }}</div>),
        "shortcodes/note"  => %(<p>{{ body }}</p>),
        "shortcodes/badge" => %(<i>{{ _0 }}</i>),
      }
      content = %({% box %}{% note %}{{ badge("a") }}{% end %}{% end %})
      result = builder.test_sc_process(content, templates)
      result.should contain("<div>")
      result.should contain("<p>")
      result.should contain("<i>a</i>")
    end
  end

  describe "argument parsing edge cases" do
    it "preserves spaces inside double-quoted values" do
      builder = Hwaro::Core::Build::Builder.new
      args = builder.test_sc_parse_args(%(title="Hello, World"))
      args["title"].should eq("Hello, World")
    end

    it "treats a value with embedded equals correctly" do
      builder = Hwaro::Core::Build::Builder.new
      args = builder.test_sc_parse_args(%(query="a=b&c=d"))
      args["query"].should eq("a=b&c=d")
    end

    it "preserves spaces inside single-quoted values" do
      builder = Hwaro::Core::Build::Builder.new
      args = builder.test_sc_parse_args(%(title='Hello World'))
      args["title"].should eq("Hello World")
    end

    it "ignores leading/trailing whitespace in positional values" do
      builder = Hwaro::Core::Build::Builder.new
      args = builder.test_sc_parse_args("  alpha , beta  ")
      args["_0"].should eq("alpha")
      args["_1"].should eq("beta")
    end
  end

  describe "placeholders" do
    it "stores rendered output behind placeholders when shortcode_results provided" do
      builder = Hwaro::Core::Build::Builder.new
      templates = {"shortcodes/note" => "<span>{{ body }}</span>"}
      results = {} of String => String

      output = builder.test_sc_process_with_results(
        "{% note %}placeheld{% end %}",
        templates,
        {} of String => Crinja::Value,
        results,
      )

      output.should contain("<!--HWARO-SHORTCODE-PLACEHOLDER-")
      results.size.should eq(1)
      results.first_value.should contain("<span>placeheld</span>")
    end

    it "produces unique placeholder ids for multiple shortcodes" do
      builder = Hwaro::Core::Build::Builder.new
      templates = {"shortcodes/note" => "<span>{{ body }}</span>"}
      results = {} of String => String

      builder.test_sc_process_with_results(
        "{% note %}a{% end %} and {% note %}b{% end %}",
        templates,
        {} of String => Crinja::Value,
        results,
      )

      results.size.should eq(2)
      results.keys.uniq!.size.should eq(2)
    end
  end
end
