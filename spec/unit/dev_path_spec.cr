require "../spec_helper"

# DevPath exists to keep the dev server's routing identical to a static
# host's. Its whole value is in the shapes it REFUSES, so those are pinned
# here directly rather than only through the HTTP handlers that call it.
describe Hwaro::Services::DevPath do
  describe ".dots_only?" do
    it "is true for the parent link" do
      Hwaro::Services::DevPath.dots_only?("..").should be_true
    end

    it "is true for the current-directory link" do
      Hwaro::Services::DevPath.dots_only?(".").should be_true
    end

    # Windows strips BOTH trailing dots and trailing ASCII spaces, which can
    # collapse these onto a segment that traverses.
    it "is true for dot/space forms Windows collapses onto . or .." do
      ["...", ".. ", ". ", "..  ", "   "].each do |segment|
        Hwaro::Services::DevPath.dots_only?(segment).should be_true
      end
    end

    # Deliberately NOT "contains ..": these are ordinary filenames a static
    # host serves, and refusing them would reintroduce dev/prod divergence.
    it "is false for ordinary names that merely contain dots" do
      ["lib.v1..2.js", "a..b", "..foo", "index.html", "a.b.c"].each do |segment|
        Hwaro::Services::DevPath.dots_only?(segment).should be_false
      end
    end

    it "is true for an empty segment" do
      Hwaro::Services::DevPath.dots_only?("").should be_true
    end

    # Only ASCII space and `.` are trimmed by Win32, so these stay distinct.
    it "is false for non-ASCII-space suffixed dot forms" do
      Hwaro::Services::DevPath.dots_only?("..\t").should be_false
      Hwaro::Services::DevPath.dots_only?(".. ").should be_false
    end
  end

  describe ".unservable?" do
    it "accepts an ordinary path" do
      Hwaro::Services::DevPath.unservable?("/guide/index.html").should be_false
    end

    it "accepts a legitimately percent-encoded non-ASCII path" do
      Hwaro::Services::DevPath.unservable?("/%ED%95%9C%EA%B8%80/").should be_false
    end

    it "accepts a raw UTF-8 path" do
      Hwaro::Services::DevPath.unservable?("/한글/").should be_false
    end

    # A static host 404s these; the dev server used to answer 200, so a broken
    # link worked locally and broke after deploy.
    it "refuses a backslash separator" do
      Hwaro::Services::DevPath.unservable?("/guide\\index.html").should be_true
    end

    it "refuses an encoded forward slash in any casing" do
      ["/%2Fguide%2Findex.html", "/%2fguide%2findex.html"].each do |path|
        Hwaro::Services::DevPath.unservable?(path).should be_true
      end
    end

    it "refuses an encoded backslash in any casing" do
      ["/guide%5Cindex.html", "/guide%5cindex.html"].each do |path|
        Hwaro::Services::DevPath.unservable?(path).should be_true
      end
    end

    # StaticFileHandler answers a decoded NUL with 400; deleting it (what the
    # lenient shared sanitizer does) served the real homepage with a 200.
    it "refuses a NUL in raw or encoded form" do
      Hwaro::Services::DevPath.unservable?("/index%00.html").should be_true
      Hwaro::Services::DevPath.unservable?("/index%2500.html").should be_false
      Hwaro::Services::DevPath.unservable?("/index\u{0000}.html").should be_true
    end

    # MUST be checked before the regexes: PCRE2 over invalid UTF-8 raises
    # ArgumentError straight out of the handler — a 500 where a static host
    # answers 404.
    it "refuses invalid UTF-8 without raising" do
      invalid = String.new(Bytes[0x2f, 0xff, 0xfe])
      invalid.valid_encoding?.should be_false
      Hwaro::Services::DevPath.unservable?(invalid).should be_true
    end

    # Double-encoded forms survive the single decode as a literal `%2f` inside
    # one segment, which simply doesn't exist on disk.
    it "does not need a separate rule for double-encoded separators" do
      Hwaro::Services::DevPath.unservable?("/guide%252findex.html").should be_false
      Hwaro::Services::DevPath.safe_relative("/guide%252findex.html").should eq("guide%2findex.html")
    end
  end

  describe ".safe_relative" do
    it "strips the leading slash" do
      Hwaro::Services::DevPath.safe_relative("/guide/index.html").should eq("guide/index.html")
    end

    it "returns an empty string for the output root itself" do
      Hwaro::Services::DevPath.safe_relative("/").should eq("")
      Hwaro::Services::DevPath.safe_relative("").should eq("")
    end

    it "collapses repeated and trailing slashes" do
      Hwaro::Services::DevPath.safe_relative("//guide///a/").should eq("guide/a")
    end

    it "drops bare current-directory segments" do
      Hwaro::Services::DevPath.safe_relative("/./guide/./a.html").should eq("guide/a.html")
    end

    it "decodes exactly once" do
      Hwaro::Services::DevPath.safe_relative("/a%20b/c.html").should eq("a b/c.html")
    end

    it "resolves a percent-encoded non-ASCII path" do
      Hwaro::Services::DevPath.safe_relative("/%ED%95%9C%EA%B8%80/").should eq("한글")
    end

    it "resolves a raw UTF-8 path" do
      Hwaro::Services::DevPath.safe_relative("/한글/index.html").should eq("한글/index.html")
    end

    it "returns nil for an unservable path" do
      ["/guide\\a.html", "/%2Fetc%2Fpasswd", "/a%00.html"].each do |path|
        Hwaro::Services::DevPath.safe_relative(path).should be_nil
      end
    end

    it "returns nil for a traversing segment" do
      ["/../etc/passwd", "/a/../../etc", "/%2e%2e/etc"].each do |path|
        Hwaro::Services::DevPath.safe_relative(path).should be_nil
      end
    end

    it "returns nil for the dot/space traversal variants" do
      ["/.. /a", "/.../a", "/a/. /b"].each do |path|
        Hwaro::Services::DevPath.safe_relative(path).should be_nil
      end
    end

    it "keeps ordinary filenames that merely contain dots" do
      Hwaro::Services::DevPath.safe_relative("/js/lib.v1..2.js").should eq("js/lib.v1..2.js")
    end

    # Percent-encoded invalid UTF-8 only becomes invalid after decoding, and
    # every operation below would raise on it.
    it "returns nil for percent-encoded invalid UTF-8 without raising" do
      ["/%c0%ae%c0%ae/etc", "/%ff"].each do |path|
        Hwaro::Services::DevPath.safe_relative(path).should be_nil
      end
    end

    it "never returns a path that escapes the output root" do
      [
        "/../a", "/..%2fa", "/%2e%2e%2fa", "/a/../../b",
        "/....//a", "/. /a", "/%2e%2e/%2e%2e/a",
      ].each do |path|
        result = Hwaro::Services::DevPath.safe_relative(path)
        next if result.nil?
        result.split('/').none? { |s| Hwaro::Services::DevPath.dots_only?(s) }.should be_true
      end
    end
  end

  describe ".encode_relative" do
    it "leaves an empty path alone" do
      Hwaro::Services::DevPath.encode_relative("").should eq("")
    end

    it "leaves an already-safe path alone" do
      Hwaro::Services::DevPath.encode_relative("guide/index.html").should eq("guide/index.html")
    end

    # safe_relative hands back decoded bytes, so a redirect built straight from
    # it would put a raw space into `Location:`.
    it "encodes a raw space" do
      Hwaro::Services::DevPath.encode_relative("a b/c.html").should eq("a%20b/c.html")
    end

    it "encodes raw UTF-8" do
      Hwaro::Services::DevPath.encode_relative("한글/a.html")
        .should eq("%ED%95%9C%EA%B8%80/a.html")
    end

    it "encodes segments but never the separator" do
      Hwaro::Services::DevPath.encode_relative("a b/c d").should eq("a%20b/c%20d")
    end

    it "round-trips back through safe_relative" do
      ["a b/c.html", "한글/a.html", "guide/index.html"].each do |relative|
        encoded = Hwaro::Services::DevPath.encode_relative(relative)
        Hwaro::Services::DevPath.safe_relative("/" + encoded).should eq(relative)
      end
    end
  end
end
