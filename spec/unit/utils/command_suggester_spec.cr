require "../../spec_helper"

# =============================================================================
# Unit spec for Hwaro::Utils::CommandSuggester — used by the CLI to provide
# "Did you mean" hints on mistyped commands / subcommands.
# =============================================================================

describe Hwaro::Utils::CommandSuggester do
  describe ".suggest" do
    it "returns the closest candidate within distance 2" do
      Hwaro::Utils::CommandSuggester.suggest(
        "buidl", ["init", "build", "serve", "deploy"]
      ).should eq("build")
    end

    it "suggests 'stats' for 'stts'" do
      Hwaro::Utils::CommandSuggester.suggest(
        "stts", ["stats", "validate", "list", "convert"]
      ).should eq("stats")
    end

    it "returns nil when no candidate is close" do
      Hwaro::Utils::CommandSuggester.suggest(
        "xyzabc", ["init", "build", "serve"]
      ).should be_nil
    end

    it "returns nil for an empty input" do
      Hwaro::Utils::CommandSuggester.suggest(
        "", ["init", "build"]
      ).should be_nil
    end

    it "leverages shared-prefix heuristic for short inputs" do
      # Edit distance between "bld" and "build" is 2, but shared prefix 'b'
      # alone is 1 char. Shared-prefix >= 3 lets longer near-misses qualify
      # without flagging every one-letter abbreviation.
      Hwaro::Utils::CommandSuggester.suggest(
        "buil", ["init", "build", "serve"]
      ).should eq("build")
    end

    it "returns nil when there are no candidates" do
      Hwaro::Utils::CommandSuggester.suggest("anything", [] of String).should be_nil
    end
  end
end
