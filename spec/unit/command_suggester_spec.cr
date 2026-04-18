require "../spec_helper"

# =============================================================================
# Unit spec for Hwaro::Utils::CommandSuggester — used by the CLI to provide
# "Did you mean" hints on mistyped commands / subcommands.
# =============================================================================

describe Hwaro::Utils::CommandSuggester do
  describe ".levenshtein" do
    it "returns 0 for identical strings" do
      Hwaro::Utils::CommandSuggester.levenshtein("build", "build").should eq(0)
    end

    it "returns edit distance for a single transposition-like typo" do
      # "buidl" → "build" is 2 single-char edits (adjacent transposition).
      Hwaro::Utils::CommandSuggester.levenshtein("buidl", "build").should eq(2)
    end

    it "returns the length when one string is empty" do
      Hwaro::Utils::CommandSuggester.levenshtein("", "build").should eq(5)
      Hwaro::Utils::CommandSuggester.levenshtein("build", "").should eq(5)
    end

    it "counts pure insertions" do
      Hwaro::Utils::CommandSuggester.levenshtein("buid", "build").should eq(1)
    end
  end

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
