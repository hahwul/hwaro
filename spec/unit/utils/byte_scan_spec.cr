require "../../spec_helper"

# ByteScan replaces `String#includes?` / `String#byte_index` on hot probe
# paths, so the contract that matters is *exact* agreement with them. The
# differential block at the bottom is the real test; the examples above it
# pin the edges that a random generator reaches only rarely.
describe Hwaro::Utils::ByteScan do
  scan = Hwaro::Utils::ByteScan

  describe ".includes?" do
    it "finds single-byte needles" do
      scan.includes?("hello", "e").should be_true
      scan.includes?("hello", "z").should be_false
    end

    it "finds multi-byte needles" do
      scan.includes?("a ~~struck~~ word", "~~").should be_true
      scan.includes?("a ~ lone tilde", "~~").should be_false
    end

    it "matches a needle at the very end of the haystack" do
      scan.includes?("prefix{#", "{#").should be_true
      # One byte short of a match: the candidate starts inside the haystack
      # but its tail runs past the end.
      scan.includes?("prefix{", "{#").should be_false
    end

    it "keeps scanning past a false first-byte hit" do
      # Every `~` before the real `~~` is a memchr hit whose memcmp fails.
      scan.includes?("~a~b~c~~", "~~").should be_true
    end

    it "treats the empty needle as present" do
      scan.includes?("abc", "").should be_true
      scan.includes?("", "").should be_true
    end

    it "reports nothing for a needle longer than the haystack" do
      scan.includes?("ab", "abc").should be_false
      scan.includes?("", "a").should be_false
    end

    it "matches needles containing NUL" do
      scan.includes?("a\u0000b", "\u0000b").should be_true
      scan.includes?("ab", "\u0000b").should be_false
    end

    it "matches multi-byte UTF-8 needles" do
      scan.includes?("한국어 문서", "국어").should be_true
      scan.includes?("한국어 문서", "일본").should be_false
      scan.includes?("emoji 🌱 here", "🌱").should be_true
    end
  end

  describe ".byte_index" do
    it "returns a byte offset, not a character offset" do
      # "한" is three bytes, so the char index of "x" is 1 but its byte index is 3.
      "한x".index("x").should eq(1)
      scan.byte_index("한x", "x").should eq(3)
    end

    it "honors a start offset" do
      scan.byte_index("aXbX", "X").should eq(1)
      scan.byte_index("aXbX", "X", 2).should eq(3)
      scan.byte_index("aXbX", "X", 4).should be_nil
    end

    it "answers nil for an out-of-range or negative start" do
      scan.byte_index("abc", "a", 99).should be_nil
      scan.byte_index("abc", "a", -1).should be_nil
    end

    it "places the empty needle at the start offset" do
      scan.byte_index("abc", "").should eq(0)
      scan.byte_index("abc", "", 2).should eq(2)
      scan.byte_index("abc", "", 3).should eq(3)
      scan.byte_index("abc", "", 4).should be_nil
    end
  end

  describe ".byte?" do
    it "detects a byte anywhere in the string" do
      scan.byte?("abc", 'b'.ord.to_u8).should be_true
      scan.byte?("abc", 'z'.ord.to_u8).should be_false
      scan.byte?("a\u0000b", 0_u8).should be_true
      scan.byte?("ab", 0_u8).should be_false
    end

    it "sees bytes inside multi-byte characters" do
      # "€" is E2 82 AC — byte?, unlike String#includes?(Char), works on bytes.
      scan.byte?("€", 0x82_u8).should be_true
    end
  end

  describe "agreement with String#includes?" do
    it "matches on random haystack/needle pairs" do
      rng = Random.new(20260908)
      alphabet = ['a', 'b', '~', '{', '#', '+', '=', '^', '[', ']', ' ', '\n', '한', '🌱']

      5_000.times do
        haystack = String.build do |io|
          rng.rand(0..24).times { io << alphabet.sample(rng) }
        end
        needle = String.build do |io|
          rng.rand(0..3).times { io << alphabet.sample(rng) }
        end

        scan.includes?(haystack, needle).should eq(haystack.includes?(needle))
      end
    end

    it "agrees with byte_index on where the first match starts" do
      rng = Random.new(9080602)
      alphabet = ['a', '~', '{', '#', ' ']

      2_000.times do
        haystack = String.build do |io|
          rng.rand(0..20).times { io << alphabet.sample(rng) }
        end
        needle = String.build do |io|
          rng.rand(1..3).times { io << alphabet.sample(rng) }
        end

        # Every byte of this alphabet outside the multi-byte chars is ASCII, so
        # the stdlib's character index and the byte index coincide and can be
        # compared directly.
        scan.byte_index(haystack, needle).should eq(haystack.index(needle))
      end
    end
  end
end
