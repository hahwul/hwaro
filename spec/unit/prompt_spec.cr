require "../spec_helper"
require "../../src/cli/prompt"

# Drive Prompt with a scripted input stream, restoring the previous one after.
private def with_prompt_input(data : String, &)
  previous = Hwaro::CLI::Prompt.input
  Hwaro::CLI::Prompt.input = IO::Memory.new(data)
  begin
    yield
  ensure
    Hwaro::CLI::Prompt.input = previous
  end
end

describe Hwaro::CLI::Prompt do
  describe ".ask" do
    it "returns the trimmed answer" do
      with_prompt_input("  hello world  \n") do
        Hwaro::CLI::Prompt.ask("Title").should eq("hello world")
      end
    end

    it "returns the default on an empty line" do
      with_prompt_input("\n") do
        Hwaro::CLI::Prompt.ask("Title", default: "seeded").should eq("seeded")
      end
    end

    it "lets a typed answer override the default" do
      with_prompt_input("typed\n") do
        Hwaro::CLI::Prompt.ask("Title", default: "seeded").should eq("typed")
      end
    end

    it "returns nil on EOF" do
      with_prompt_input("") do
        Hwaro::CLI::Prompt.ask("Title").should be_nil
      end
    end

    it "returns nil for an empty line with no default" do
      with_prompt_input("\n") do
        Hwaro::CLI::Prompt.ask("Description").should be_nil
      end
    end
  end

  describe ".ask_required" do
    it "re-prompts until a non-empty answer arrives" do
      with_prompt_input("\n   \nfinally\n") do
        Hwaro::CLI::Prompt.ask_required("Title").should eq("finally")
      end
    end

    it "returns nil on EOF" do
      with_prompt_input("") do
        Hwaro::CLI::Prompt.ask_required("Title").should be_nil
      end
    end
  end

  describe ".confirm?" do
    it "treats y / yes as true" do
      with_prompt_input("y\n") { Hwaro::CLI::Prompt.confirm?("ok?").should be_true }
      with_prompt_input("YES\n") { Hwaro::CLI::Prompt.confirm?("ok?").should be_true }
    end

    it "treats other input as false" do
      with_prompt_input("n\n") { Hwaro::CLI::Prompt.confirm?("ok?").should be_false }
      with_prompt_input("nope\n") { Hwaro::CLI::Prompt.confirm?("ok?").should be_false }
    end

    it "uses the default on an empty line" do
      with_prompt_input("\n") { Hwaro::CLI::Prompt.confirm?("ok?", default: true).should be_true }
      with_prompt_input("\n") { Hwaro::CLI::Prompt.confirm?("ok?", default: false).should be_false }
    end

    it "returns nil on EOF" do
      with_prompt_input("") { Hwaro::CLI::Prompt.confirm?("ok?").should be_nil }
    end
  end

  describe ".select" do
    it "returns the choice by 1-based index" do
      with_prompt_input("2\n") do
        Hwaro::CLI::Prompt.select("Pick", ["a", "b", "c"]).should eq("b")
      end
    end

    it "returns the choice by exact name" do
      with_prompt_input("c\n") do
        Hwaro::CLI::Prompt.select("Pick", ["a", "b", "c"]).should eq("c")
      end
    end

    it "returns nil when skipped with an empty line" do
      with_prompt_input("\n") do
        Hwaro::CLI::Prompt.select("Pick", ["a", "b"]).should be_nil
      end
    end

    it "re-prompts on an unrecognised entry, then accepts a valid one" do
      with_prompt_input("9\nzzz\n1\n") do
        Hwaro::CLI::Prompt.select("Pick", ["a", "b"]).should eq("a")
      end
    end

    it "returns nil immediately for an empty choice list" do
      with_prompt_input("anything\n") do
        Hwaro::CLI::Prompt.select("Pick", [] of String).should be_nil
      end
    end
  end
end
