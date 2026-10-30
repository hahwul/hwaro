require "../../../../spec_helper"
require "../../../../../src/content/processors/template"

module Hwaro::Content::Processors::Filters::StringFilters
  def self.regex_cache_size : Int32
    @@regex_mutex.synchronize { @@regex_cache.size }
  end
end

private def expect_template_error(source : String, message : String, vars = {} of String => Crinja::Value)
  ex = expect_raises(Crinja::Error) { render_crinja(source, vars) }
  ex.message.not_nil!.should contain(message)
end

describe Hwaro::Content::Processors::Filters::StringFilters do
  describe "regex_replace" do
    it "replaces every match, with Zola's named or positional arguments" do
      render_crinja(%({{ "a1b22c333" | regex_replace(pattern="[0-9]+", rep="#") }})).should eq("a#b#c#")
      render_crinja(%({{ "a1b22" | regex_replace("[0-9]+", "-") }})).should eq("a-b-")
    end

    it "expands $N, ${N}, $name, ${name} and $$ like Rust's regex" do
      render_crinja(%({{ "2024-03-05" | regex_replace(pattern="(\\\\d+)-(\\\\d+)-(\\\\d+)", rep="$3/$2/$1") }})).should eq("05/03/2024")
      render_crinja(%({{ "ab" | regex_replace(pattern="(a)(b)", rep="${2}x${1}") }})).should eq("bxa")
      render_crinja(%({{ "John Smith" | regex_replace(pattern="(?<first>\\\\w+) (?<last>\\\\w+)", rep="$last, ${first}") }})).should eq("Smith, John")
      render_crinja(%({{ "5" | regex_replace(pattern="(\\\\d)", rep="$$$1") }})).should eq("$5")
    end

    it "follows Rust for unknown groups, bare dollars and backslashes" do
      # `$1a` names group "1a", which does not exist.
      render_crinja(%({{ "ab" | regex_replace(pattern="(a)", rep="$1a") }})).should eq("b")
      render_crinja(%({{ "ab" | regex_replace(pattern="(a)", rep="${9}${nope}") }})).should eq("b")
      render_crinja(%({{ "ab" | regex_replace(pattern="a", rep="$ ${") }})).should eq("$ ${b")
      render_crinja(%({{ "ab" | regex_replace(pattern="(a)", rep="\\\\1") }})).should eq("\\1b")
      # An optional group that did not take part in the match is empty.
      render_crinja(%({{ "b" | regex_replace(pattern="(a)?b", rep="[$1]") }})).should eq("[]")
    end

    it "removes matches when rep is omitted" do
      render_crinja(%({{ "a b  c" | regex_replace(pattern="\\\\s+") }})).should eq("abc")
    end

    it "stringifies a non-string target and leaves an undefined one empty" do
      render_crinja(%({{ 12345 | regex_replace(pattern="3", rep="_") }})).should eq("12_45")
      render_crinja(%(<{{ nope | regex_replace(pattern="a", rep="b") }}>)).should eq("<>")
    end

    it "raises a template error for an invalid or missing pattern" do
      expect_template_error("{{ \"x\" | regex_replace(pattern=\"(\", rep=\"\") }}", "regex_replace: invalid pattern \"(\"")
      expect_template_error(%({{ "x" | regex_replace(rep="y") }}), "regex_replace requires a pattern")
    end

    it "raises a template error when matching hits PCRE2's backtracking limit" do
      vars = {"s" => Crinja::Value.new("a" * 40 + "b")}
      expect_template_error(%({{ s | regex_replace(pattern="(a+)+$", rep="") }}), "regex_replace: ", vars)
    end

    it "does not crash on invalid UTF-8 input (it is scrubbed first)" do
      vars = {"s" => Crinja::Value.new(String.new(Bytes[0x61, 0xff, 0x62]))}
      render_crinja(%({{ s | regex_replace(pattern="b", rep="c") }}), vars).should eq("a�c")
    end

    it "skips an empty match that touches the previous match, like Rust and Go" do
      render_crinja(%({{ "aab" | regex_replace(pattern="a*", rep="-") }})).should eq("-b-")
      render_crinja(%({{ "xx" | regex_replace(pattern="x*", rep="-") }})).should eq("-")
      render_crinja(%({{ "abc" | regex_replace(pattern="", rep="-") }})).should eq("-a-b-c-")
      # Empty matches advance by a character, not a byte.
      render_crinja(%({{ "한é" | regex_replace(pattern="x*", rep="|") }})).should eq("|한|é|")
      render_crinja(%({{ "b한b" | regex_replace(pattern="b*", rep="-") }})).should eq("-한-")
    end
  end

  describe ".regex" do
    it "returns the cached regex until it is evicted, then compiles it afresh" do
      filters = Hwaro::Content::Processors::Filters::StringFilters
      first = filters.regex("evict-me")
      filters.regex("evict-me").should be(first)
      Hwaro::Content::Processors::Filters::StringFilters::REGEX_CACHE_SIZE.times { |i| filters.regex("evict-filler-#{i}") }
      filters.regex_cache_size.should eq(Hwaro::Content::Processors::Filters::StringFilters::REGEX_CACHE_SIZE)
      again = filters.regex("evict-me")
      again.should_not be(first)
      again.should eq(first)
    end

    it "stays consistent and bounded under parallel workers" do
      filters = Hwaro::Content::Processors::Filters::StringFilters
      results = Channel(Bool).new
      ctx = Fiber::ExecutionContext::Parallel.new("regex-cache-spec", 8)
      8.times do |worker|
        ctx.spawn do
          ok = true
          # Overlapping pattern sets well past the bound: constant eviction.
          400.times do |n|
            pattern = "par-#{(worker * 97 + n) % 1000}"
            ok &&= filters.regex(pattern).source == pattern
          end
          results.send(ok)
        end
      end
      8.times { results.receive.should be_true }
      filters.regex_cache_size.should be <= Hwaro::Content::Processors::Filters::StringFilters::REGEX_CACHE_SIZE
    end
  end

  describe "base64_encode / base64_decode" do
    it "round-trips UTF-8 text" do
      render_crinja(%({{ "héllo 한" | base64_encode }})).should eq(Base64.strict_encode("héllo 한"))
      render_crinja(%({{ "héllo 한" | base64_encode | base64_decode }})).should eq("héllo 한")
      render_crinja(%(<{{ "" | base64_encode }}>)).should eq("<>")
    end

    it "decodes the URL-safe alphabet and unpadded input" do
      render_crinja(%({{ "aGVsbG8" | base64_decode }})).should eq("hello")
      render_crinja(%({{ "PDw_Pz4-" | base64_decode }})).should eq("<<??>>")
    end

    it "raises a template error for invalid input or non-UTF-8 bytes" do
      expect_template_error(%({{ "@@@" | base64_decode }}), "base64_decode: invalid base64 input")
      expect_template_error(%({{ "/w==" | base64_decode }}), "base64_decode: decoded bytes are not valid UTF-8")
    end
  end

  describe "hash filters" do
    it "returns the lowercase hex digest of the UTF-8 string" do
      render_crinja(%({{ "abc" | md5 }})).should eq("900150983cd24fb0d6963f7d28e17f72")
      render_crinja(%({{ "abc" | sha1 }})).should eq("a9993e364706816aba3e25717850c26c9cd0d89d")
      render_crinja(%({{ "abc" | sha256 }})).should eq("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
      render_crinja(%({{ "abc" | sha384 }})).should start_with("cb00753f45a35e8b")
      render_crinja(%({{ "abc" | sha512 }})).should start_with("ddaf35a193617aba")
      render_crinja(%({{ "" | md5 }})).should eq("d41d8cd98f00b204e9800998ecf8427e")
    end

    it "returns base64 with base64=true, matching the SRI format" do
      render_crinja(%({{ "abc" | sha256(base64=true) }})).should eq("ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=")
      render_crinja(%(sha384-{{ "body{}" | sha384(base64=true) }})).should eq(Hwaro::Utils::DigestUtils.sri("body{}"))
    end
  end
end
