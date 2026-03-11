require "../spec_helper"
require "../../src/content/processors/base"

# Concrete test processor for testing the abstract Base class
private class TestProcessor < Hwaro::Content::Processors::Base
  def name : String
    "test-processor"
  end

  def extensions : Array(String)
    [".md", ".markdown"]
  end

  def process(content : String, context : Hwaro::Content::Processors::ProcessorContext) : Hwaro::Content::Processors::ProcessorResult
    Hwaro::Content::Processors::ProcessorResult.new(content: content.upcase)
  end
end

private class HighPriorityProcessor < Hwaro::Content::Processors::Base
  def name : String
    "high-priority"
  end

  def extensions : Array(String)
    [".html"]
  end

  def priority : Int32
    10
  end

  def process(content : String, context : Hwaro::Content::Processors::ProcessorContext) : Hwaro::Content::Processors::ProcessorResult
    Hwaro::Content::Processors::ProcessorResult.new(content: content)
  end
end

describe Hwaro::Content::Processors::ProcessorContext do
  it "has default values" do
    ctx = Hwaro::Content::Processors::ProcessorContext.new
    ctx.file_path.should eq("")
    ctx.output_path.should eq("")
    ctx.config.should be_empty
  end

  it "accepts custom values" do
    ctx = Hwaro::Content::Processors::ProcessorContext.new(
      file_path: "content/post.md",
      output_path: "public/post/index.html",
      config: {"key" => "value"}
    )
    ctx.file_path.should eq("content/post.md")
    ctx.output_path.should eq("public/post/index.html")
    ctx.config["key"].should eq("value")
  end
end

describe Hwaro::Content::Processors::ProcessorResult do
  it "defaults to success" do
    result = Hwaro::Content::Processors::ProcessorResult.new(content: "hello")
    result.content.should eq("hello")
    result.success.should be_true
    result.error.should be_nil
    result.metadata.should be_empty
  end

  it "accepts metadata" do
    result = Hwaro::Content::Processors::ProcessorResult.new(
      content: "hello",
      metadata: {"word_count" => "1"}
    )
    result.metadata["word_count"].should eq("1")
  end

  describe ".error" do
    it "creates a failed result" do
      result = Hwaro::Content::Processors::ProcessorResult.error("something went wrong")
      result.success.should be_false
      result.content.should eq("")
      result.error.should eq("something went wrong")
    end
  end
end

describe Hwaro::Content::Processors::Base do
  describe "#can_process?" do
    it "returns true for matching extensions" do
      processor = TestProcessor.new
      processor.can_process?("post.md").should be_true
      processor.can_process?("post.markdown").should be_true
    end

    it "returns false for non-matching extensions" do
      processor = TestProcessor.new
      processor.can_process?("post.html").should be_false
      processor.can_process?("post.txt").should be_false
    end

    it "is case-insensitive for extensions" do
      processor = TestProcessor.new
      processor.can_process?("post.MD").should be_true
    end
  end

  describe "#priority" do
    it "defaults to 0" do
      processor = TestProcessor.new
      processor.priority.should eq(0)
    end

    it "can be overridden" do
      processor = HighPriorityProcessor.new
      processor.priority.should eq(10)
    end
  end
end

describe "Hwaro::Content::Processors::Registry (isolated)" do
  # Test registry behavior without clearing global state.
  # We register test processors, verify them, then clean up only what we added.

  it "can register and retrieve a test processor" do
    processor = TestProcessor.new
    Hwaro::Content::Processors::Registry.register(processor)
    Hwaro::Content::Processors::Registry.get("test-processor").should eq(processor)
  end

  it "returns nil for unregistered processor name" do
    Hwaro::Content::Processors::Registry.get("__nonexistent_test__").should be_nil
  end

  it "has? returns true for registered test processor" do
    Hwaro::Content::Processors::Registry.register(TestProcessor.new)
    Hwaro::Content::Processors::Registry.has?("test-processor").should be_true
  end

  it "has? returns false for unregistered name" do
    Hwaro::Content::Processors::Registry.has?("__nonexistent_test__").should be_false
  end

  it "names includes registered test processors" do
    Hwaro::Content::Processors::Registry.register(TestProcessor.new)
    Hwaro::Content::Processors::Registry.register(HighPriorityProcessor.new)
    names = Hwaro::Content::Processors::Registry.names
    names.should contain("test-processor")
    names.should contain("high-priority")
  end

  it "all returns processors including test processors sorted by priority" do
    Hwaro::Content::Processors::Registry.register(TestProcessor.new)
    Hwaro::Content::Processors::Registry.register(HighPriorityProcessor.new)

    all = Hwaro::Content::Processors::Registry.all
    # high-priority (10) should come before test-processor (0)
    hp_idx = all.index { |p| p.name == "high-priority" }
    tp_idx = all.index { |p| p.name == "test-processor" }
    hp_idx.should_not be_nil
    tp_idx.should_not be_nil
    hp_idx.not_nil!.should be < tp_idx.not_nil!
  end

  it "for_file returns matching processors" do
    Hwaro::Content::Processors::Registry.register(TestProcessor.new)
    Hwaro::Content::Processors::Registry.register(HighPriorityProcessor.new)

    md_processors = Hwaro::Content::Processors::Registry.for_file("post.md")
    md_names = md_processors.map(&.name)
    md_names.should contain("test-processor")

    html_processors = Hwaro::Content::Processors::Registry.for_file("page.html")
    html_names = html_processors.map(&.name)
    html_names.should contain("high-priority")
  end

  it "for_file returns empty for unmatched extensions" do
    Hwaro::Content::Processors::Registry.for_file("image.png").select { |p|
      p.name == "test-processor" || p.name == "high-priority"
    }.should be_empty
  end
end
