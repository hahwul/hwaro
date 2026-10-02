require "../../../spec_helper"
require "../../../../src/content/processors/markdown"

# =============================================================================
# Gap-filling unit specs for content processors that complement the existing
# coverage in frontmatter_parsing_spec.cr, processors_spec.cr, etc.
#
# Targets behaviors not exercised elsewhere:
# - Front-matter typo warning (Levenshtein-based)
# =============================================================================

describe Hwaro::Content::Processors::Markdown do
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

    it "suggests the closest known key, not merely the first within threshold" do
      # `tag` is distance 1 from `tags` but distance 2 from `toc`. Because
      # `toc` precedes `tags` in KNOWN_FRONT_MATTER_KEYS, a first-match scan
      # would wrongly suggest `toc`; the suggester must pick the closest key.
      previous_io = Hwaro::Logger.io
      sink = IO::Memory.new
      Hwaro::Logger.io = sink

      begin
        md = Hwaro::Content::Processors::Markdown.new
        md.parse("---\ntag: x\n---\nbody", "test.md")
        out = sink.to_s
        out.should contain("did you mean 'tags'")
        out.should_not contain("'toc'")
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
