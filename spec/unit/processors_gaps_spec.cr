require "../spec_helper"
require "../../src/content/processors/base"
require "../../src/content/processors/markdown"

# =============================================================================
# Gap-filling unit specs for content processors that complement the existing
# coverage in processor_base_spec.cr, frontmatter_parsing_spec.cr,
# processors_spec.cr, processors_html_spec.cr, json_xml_processors_spec.cr,
# content_files_processor_spec.cr, etc.
#
# Targets behaviors not exercised elsewhere:
# - Registry.clear (with snapshot/restore so other specs aren't affected)
# - Registry.register invalidating its sorted-by-priority cache
# - Markdown#process (Base interface) — wraps render and returns ProcessorResult
# - Markdown#process error path
# - Front-matter typo warning (Levenshtein-based)
# =============================================================================

private class GapTestProcessor < Hwaro::Content::Processors::Base
  def name : String
    "gap-test-processor"
  end

  def extensions : Array(String)
    [".gap"]
  end

  def process(content : String, context : Hwaro::Content::Processors::ProcessorContext) : Hwaro::Content::Processors::ProcessorResult
    Hwaro::Content::Processors::ProcessorResult.new(content: content)
  end
end

private class GapHigherProcessor < GapTestProcessor
  def name : String
    "gap-higher"
  end

  def priority : Int32
    99
  end
end

# Capture and restore the registry around each test so we don't pollute other
# specs that depend on the default-registered processors (markdown, html, ...).
#
# NOTE: The snapshot stores references to processor instances, not clones.
# Tests inside the block must NOT mutate any processor's internal state, or
# the restore will put a mutated instance back into the global registry.
private def with_registry_snapshot(&)
  snapshot = {} of String => Hwaro::Content::Processors::Base
  Hwaro::Content::Processors::Registry.names.each do |n|
    if p = Hwaro::Content::Processors::Registry.get(n)
      snapshot[n] = p
    end
  end

  begin
    yield
  ensure
    Hwaro::Content::Processors::Registry.clear
    snapshot.each_value { |p| Hwaro::Content::Processors::Registry.register(p) }
  end
end

describe Hwaro::Content::Processors::Registry do
  describe ".clear" do
    it "removes every registered processor" do
      with_registry_snapshot do
        Hwaro::Content::Processors::Registry.register(GapTestProcessor.new)
        Hwaro::Content::Processors::Registry.has?("gap-test-processor").should be_true

        Hwaro::Content::Processors::Registry.clear
        Hwaro::Content::Processors::Registry.has?("gap-test-processor").should be_false
        Hwaro::Content::Processors::Registry.names.should be_empty
        Hwaro::Content::Processors::Registry.all.should be_empty
      end
    end

    it "is safe to call when the registry is already empty" do
      with_registry_snapshot do
        Hwaro::Content::Processors::Registry.clear
        Hwaro::Content::Processors::Registry.clear
        Hwaro::Content::Processors::Registry.all.should be_empty
      end
    end
  end

  describe "sort cache invalidation on register" do
    it "rebuilds the priority-sorted list when a new processor is registered" do
      with_registry_snapshot do
        Hwaro::Content::Processors::Registry.clear
        Hwaro::Content::Processors::Registry.register(GapTestProcessor.new)
        # Warm the cache: priority-0 processor is the only entry
        Hwaro::Content::Processors::Registry.all.first.name.should eq("gap-test-processor")

        # Register a higher-priority processor; the cached array must be rebuilt
        Hwaro::Content::Processors::Registry.register(GapHigherProcessor.new)
        Hwaro::Content::Processors::Registry.all.first.name.should eq("gap-higher")
      end
    end
  end

  describe ".for_file" do
    it "returns truly empty when no registered processor matches the extension" do
      with_registry_snapshot do
        Hwaro::Content::Processors::Registry.clear
        Hwaro::Content::Processors::Registry.register(GapTestProcessor.new)
        Hwaro::Content::Processors::Registry.for_file("image.png").should be_empty
      end
    end
  end
end

describe Hwaro::Content::Processors::Markdown do
  describe "#process (Base interface)" do
    it "wraps render and returns a successful ProcessorResult" do
      md = Hwaro::Content::Processors::Markdown.new
      ctx = Hwaro::Content::Processors::ProcessorContext.new
      result = md.process("# Hello\n\nWorld", ctx)

      result.success.should be_true
      result.error.should be_nil
      result.content.should contain("Hello")
      # Regex match avoids false positives like <h10> while still allowing
      # <h1> with arbitrary attributes (e.g. <h1 id="hello">).
      result.content.should match(/<h1[\s>]/)
    end

    it "returns an empty (but successful) result for empty input" do
      md = Hwaro::Content::Processors::Markdown.new
      ctx = Hwaro::Content::Processors::ProcessorContext.new
      result = md.process("", ctx)
      result.success.should be_true
      result.content.should eq("")
    end

    it "renders inline elements and lists" do
      md = Hwaro::Content::Processors::Markdown.new
      ctx = Hwaro::Content::Processors::ProcessorContext.new
      result = md.process("- one\n- two\n\n**bold**", ctx)
      result.success.should be_true
      result.content.should contain("<ul")
      result.content.should contain("<strong>")
    end
  end

  describe "front-matter typo warning" do
    it "warns when an unknown key is within Levenshtein distance 2 of a known key" do
      # Precondition: the test's setup assumes `title` is a known key.
      # If KNOWN_FRONT_MATTER_KEYS ever drops it, the typo logic would
      # silently match a different key (or none), and the test below would
      # pass for the wrong reason.
      Hwaro::Content::Processors::Markdown::KNOWN_FRONT_MATTER_KEYS
        .includes?("title").should be_true

      previous_io = Hwaro::Logger.io
      sink = IO::Memory.new
      Hwaro::Logger.io = sink

      begin
        md = Hwaro::Content::Processors::Markdown.new
        # `titel` is one edit away from `title` — should trigger a warning
        md.parse("---\ntitel: Hello\n---\nbody", "test.md")
        sink.to_s.should contain("titel")
        sink.to_s.should contain("did you mean")
        sink.to_s.should contain("title")
      ensure
        Hwaro::Logger.io = previous_io
      end
    end

    it "does not warn for keys far from any known key (likely intentional)" do
      previous_io = Hwaro::Logger.io
      sink = IO::Memory.new
      Hwaro::Logger.io = sink

      begin
        md = Hwaro::Content::Processors::Markdown.new
        # `custom_field_xyz` is far from every KNOWN_FRONT_MATTER_KEYS entry
        md.parse(%(---\ncustom_field_xyz: "value"\n---\nbody), "test.md")
        sink.to_s.should_not contain("did you mean")
      ensure
        Hwaro::Logger.io = previous_io
      end
    end

    it "does not warn for known keys" do
      previous_io = Hwaro::Logger.io
      sink = IO::Memory.new
      Hwaro::Logger.io = sink

      begin
        md = Hwaro::Content::Processors::Markdown.new
        md.parse("---\ntitle: Hello\ndraft: false\n---\nbody", "test.md")
        sink.to_s.should_not contain("did you mean")
      ensure
        Hwaro::Logger.io = previous_io
      end
    end

    it "skips warnings entirely when file_path is empty" do
      previous_io = Hwaro::Logger.io
      sink = IO::Memory.new
      Hwaro::Logger.io = sink

      begin
        md = Hwaro::Content::Processors::Markdown.new
        md.parse("---\ntitel: Hello\n---\nbody", "")
        sink.to_s.should_not contain("did you mean")
      ensure
        Hwaro::Logger.io = previous_io
      end
    end
  end
end
