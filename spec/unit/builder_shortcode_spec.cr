require "../spec_helper"
require "../../src/core/build/builder"

# Reopen Builder to expose private methods for testing
module Hwaro::Core::Build
  class Builder
    def test_parse_shortcode_args_jinja(args_str)
      parse_shortcode_args_jinja(args_str)
    end

    def test_process_shortcodes_jinja(content, templates, context, shortcode_results = nil, crinja_env_override = nil)
      process_shortcodes_jinja(content, templates, context, shortcode_results, crinja_env_override: crinja_env_override)
    end

    def test_render_shortcode_result(name, args_str, templates, context, shortcode_results, fallback, warn_missing = true, extra_args = nil, crinja_env_override = nil)
      render_shortcode_result(name, args_str, templates, context, shortcode_results, fallback, warn_missing: warn_missing, extra_args: extra_args, crinja_env_override: crinja_env_override)
    end

    def test_replace_shortcode_placeholders(html, shortcode_results)
      replace_shortcode_placeholders(html, shortcode_results)
    end

    def test_render_shortcode_jinja(template, args, context, crinja_env_override = nil)
      render_shortcode_jinja(template, args, context, crinja_env_override: crinja_env_override)
    end
  end
end

describe Hwaro::Core::Build::Builder do
  describe "#parse_shortcode_args_jinja" do
    it "parses quoted and unquoted arguments" do
      builder = Hwaro::Core::Build::Builder.new
      args = builder.test_parse_shortcode_args_jinja("key1=\"value 1\" key2='value 2' key3=value3")

      args["key1"].should eq("value 1")
      args["key2"].should eq("value 2")
      args["key3"].should eq("value3")
    end

    it "handles empty arguments" do
      builder = Hwaro::Core::Build::Builder.new
      args = builder.test_parse_shortcode_args_jinja("")
      args.should be_empty
    end

    it "handles nil arguments" do
      builder = Hwaro::Core::Build::Builder.new
      args = builder.test_parse_shortcode_args_jinja(nil)
      args.should be_empty
    end

    it "parses arguments with whitespace" do
      builder = Hwaro::Core::Build::Builder.new
      args = builder.test_parse_shortcode_args_jinja("key1 = \"value1\"  key2=  'value2'")

      args["key1"].should eq("value1")
      args["key2"].should eq("value2")
    end
  end

  describe "#process_shortcodes_jinja" do
    it "processes block shortcodes" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new
      templates = {"shortcodes/note" => "<div class=\"note\">{{ body }}</div>"}
      context = {} of String => Crinja::Value

      content = "{% note(type=\"warning\") %}This is important{% end %}"
      result = builder.test_process_shortcodes_jinja(content, templates, context, crinja_env_override: env)
      result.should contain("<div class=\"note\">This is important</div>")
    end

    it "processes explicit shortcode calls" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new
      templates = {"shortcodes/youtube" => "<iframe src=\"https://youtube.com/embed/{{ id }}\"></iframe>"}
      context = {} of String => Crinja::Value

      content = "{{ shortcode(\"youtube\", id=\"abc123\") }}"
      result = builder.test_process_shortcodes_jinja(content, templates, context, crinja_env_override: env)
      result.should contain("<iframe src=\"https://youtube.com/embed/abc123\"></iframe>")
    end

    it "processes direct shortcode calls" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new
      templates = {"shortcodes/greeting" => "<p>Hello {{ name }}!</p>"}
      context = {} of String => Crinja::Value

      content = "{{ greeting(name=\"World\") }}"
      result = builder.test_process_shortcodes_jinja(content, templates, context, crinja_env_override: env)
      result.should contain("<p>Hello World!</p>")
    end

    it "skips shortcodes inside backtick code fences" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new
      templates = {"shortcodes/note" => "<div>{{ body }}</div>"}
      context = {} of String => Crinja::Value

      content = "```\n{{ shortcode(\"note\", text=\"skip\") }}\n```"
      result = builder.test_process_shortcodes_jinja(content, templates, context, crinja_env_override: env)
      result.should contain("{{ shortcode(\"note\", text=\"skip\") }}")
    end

    it "skips shortcodes inside tilde code fences" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new
      templates = {"shortcodes/note" => "<div>{{ body }}</div>"}
      context = {} of String => Crinja::Value

      content = "~~~\n{{ shortcode(\"note\", text=\"skip\") }}\n~~~"
      result = builder.test_process_shortcodes_jinja(content, templates, context, crinja_env_override: env)
      result.should contain("{{ shortcode(\"note\", text=\"skip\") }}")
    end

    it "processes shortcodes outside code fences but skips inside" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new
      templates = {"shortcodes/greeting" => "<p>{{ name }}</p>"}
      context = {} of String => Crinja::Value

      content = "{{ greeting(name=\"before\") }}\n```\n{{ greeting(name=\"inside\") }}\n```\n{{ greeting(name=\"after\") }}"
      result = builder.test_process_shortcodes_jinja(content, templates, context, crinja_env_override: env)
      result.should contain("<p>before</p>")
      result.should contain("{{ greeting(name=\"inside\") }}")
      result.should contain("<p>after</p>")
    end

    it "stores results in shortcode_results when provided" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new
      templates = {"shortcodes/test" => "<b>{{ val }}</b>"}
      context = {} of String => Crinja::Value
      shortcode_results = {} of String => String

      content = "{{ test(val=\"hello\") }}"
      result = builder.test_process_shortcodes_jinja(content, templates, context, shortcode_results, crinja_env_override: env)
      result.should contain("HWARO-SHORTCODE-PLACEHOLDER-")
      shortcode_results.size.should eq(1)
      shortcode_results.values.first.should eq("<b>hello</b>")
    end
  end

  describe "#render_shortcode_result" do
    it "renders a shortcode template and returns HTML" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new
      templates = {"shortcodes/box" => "<div>{{ text }}</div>"}
      context = {} of String => Crinja::Value

      result = builder.test_render_shortcode_result(
        "box", "text=\"content\"", templates, context, nil, "fallback", crinja_env_override: env
      )
      result.should eq("<div>content</div>")
    end

    it "stores result as placeholder when shortcode_results provided" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new
      templates = {"shortcodes/box" => "<div>{{ text }}</div>"}
      context = {} of String => Crinja::Value
      shortcode_results = {} of String => String

      result = builder.test_render_shortcode_result(
        "box", "text=\"hi\"", templates, context, shortcode_results, "fallback", crinja_env_override: env
      )
      result.should eq("HWARO-SHORTCODE-PLACEHOLDER-0")
      shortcode_results["HWARO-SHORTCODE-PLACEHOLDER-0"].should eq("<div>hi</div>")
    end

    it "returns fallback when template not found" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new
      templates = {} of String => String
      context = {} of String => Crinja::Value

      result = builder.test_render_shortcode_result(
        "missing", nil, templates, context, nil, "{{ missing() }}", warn_missing: false, crinja_env_override: env
      )
      result.should eq("{{ missing() }}")
    end

    it "passes extra_args to the template" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new
      templates = {"shortcodes/wrap" => "<div>{{ body }}</div>"}
      context = {} of String => Crinja::Value
      extra = {"body" => "inner content"}

      result = builder.test_render_shortcode_result(
        "wrap", nil, templates, context, nil, "fallback", extra_args: extra, crinja_env_override: env
      )
      result.should eq("<div>inner content</div>")
    end
  end

  describe "#replace_shortcode_placeholders" do
    it "replaces placeholders with rendered HTML" do
      builder = Hwaro::Core::Build::Builder.new
      results = {
        "HWARO-SHORTCODE-PLACEHOLDER-0" => "<b>bold</b>",
        "HWARO-SHORTCODE-PLACEHOLDER-1" => "<i>italic</i>",
      }

      html = "<p>HWARO-SHORTCODE-PLACEHOLDER-0 and HWARO-SHORTCODE-PLACEHOLDER-1</p>"
      output = builder.test_replace_shortcode_placeholders(html, results)
      output.should eq("<p><b>bold</b> and <i>italic</i></p>")
    end

    it "returns html unchanged when results are empty" do
      builder = Hwaro::Core::Build::Builder.new
      results = {} of String => String

      html = "<p>no placeholders</p>"
      output = builder.test_replace_shortcode_placeholders(html, results)
      output.should eq("<p>no placeholders</p>")
    end

    it "keeps unmatched placeholders as-is" do
      builder = Hwaro::Core::Build::Builder.new
      results = {
        "HWARO-SHORTCODE-PLACEHOLDER-0" => "<b>found</b>",
      }

      html = "HWARO-SHORTCODE-PLACEHOLDER-0 HWARO-SHORTCODE-PLACEHOLDER-99"
      output = builder.test_replace_shortcode_placeholders(html, results)
      output.should eq("<b>found</b> HWARO-SHORTCODE-PLACEHOLDER-99")
    end
  end

  describe "#render_shortcode_jinja" do
    it "renders a template with args and context" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new
      template = "<span>{{ greeting }} {{ name }}</span>"
      args = {"name" => "World"}
      context = {"greeting" => Crinja::Value.new("Hello")} of String => Crinja::Value

      result = builder.test_render_shortcode_jinja(template, args, context, crinja_env_override: env)
      result.should eq("<span>Hello World</span>")
    end

    it "returns empty string on template syntax error" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new
      template = "{% if %}"
      args = {} of String => String
      context = {} of String => Crinja::Value

      result = builder.test_render_shortcode_jinja(template, args, context, crinja_env_override: env)
      result.should eq("")
    end

    it "args override context values" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new
      template = "{{ val }}"
      args = {"val" => "from_args"}
      context = {"val" => Crinja::Value.new("from_context")} of String => Crinja::Value

      result = builder.test_render_shortcode_jinja(template, args, context, crinja_env_override: env)
      result.should eq("from_args")
    end
  end

  describe "positional arguments" do
    it "parses positional string arguments as _0, _1, etc" do
      builder = Hwaro::Core::Build::Builder.new
      args = builder.test_parse_shortcode_args_jinja(%("warning", "Be careful!"))
      args["_0"].should eq("warning")
      args["_1"].should eq("Be careful!")
    end

    it "parses single positional argument" do
      builder = Hwaro::Core::Build::Builder.new
      args = builder.test_parse_shortcode_args_jinja(%("hello"))
      args["_0"].should eq("hello")
    end

    it "prefers named args when = is present" do
      builder = Hwaro::Core::Build::Builder.new
      args = builder.test_parse_shortcode_args_jinja(%(type="warning"))
      args["type"].should eq("warning")
      args.has_key?("_0").should be_false
    end

    it "renders shortcode with positional args" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new
      template = "{{ _0 }}: {{ _1 }}"
      args = {"_0" => "alert", "_1" => "message"}
      context = {} of String => Crinja::Value

      result = builder.test_render_shortcode_jinja(template, args, context, crinja_env_override: env)
      result.should eq("alert: message")
    end
  end

  describe "nested shortcodes" do
    it "processes shortcodes nested inside block body" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new

      templates = {
        "shortcodes/outer" => "<div>{{ body }}</div>",
        "shortcodes/inner" => "<em>{{ text }}</em>",
      }
      context = {} of String => Crinja::Value
      content = "{% outer() %}{{ inner(text=\"nested\") }}{% end %}"

      result = builder.test_process_shortcodes_jinja(content, templates, context, crinja_env_override: env)
      result.should contain("<div>")
      result.should contain("<em>nested</em>")
    end
  end

  describe "markdown in shortcode body" do
    it "passes raw body to shortcode template without automatic markdown conversion" do
      builder = Hwaro::Core::Build::Builder.new
      env = Crinja.new

      templates = {
        "shortcodes/note" => "<div class=\"note\">{{ body }}</div>",
      }
      context = {} of String => Crinja::Value
      content = "{% note() %}\n**bold** text\n{% end %}"

      result = builder.test_process_shortcodes_jinja(content, templates, context, crinja_env_override: env)
      # Body is passed as-is; markdown conversion is the template's responsibility
      result.should contain("**bold** text")
      result.should contain("note")
    end
  end
end
