require "../../spec_helper"

# One implementation backs every fingerprint site (template/config checksums,
# the data-directory digest, cascade fingerprints). If the length prefix ever
# drops out, two different inputs hash identically and a stale cache is served
# forever — so the anti-ambiguity property is pinned directly here.
private def digest_of(*values : String) : String
  digest = Digest::SHA256.new
  values.each { |v| Hwaro::Utils::DigestUtils.update_length_prefixed(digest, v) }
  digest.hexfinal
end

describe Hwaro::Utils::DigestUtils do
  describe ".update_length_prefixed" do
    it "is deterministic for the same input" do
      digest_of("a", "bc").should eq(digest_of("a", "bc"))
    end

    # The whole point: "a"+"bc" and "ab"+"c" concatenate to the same bytes.
    it "distinguishes field boundaries that concatenate identically" do
      digest_of("a", "bc").should_not eq(digest_of("ab", "c"))
    end

    it "distinguishes a split field from the joined one" do
      digest_of("ab").should_not eq(digest_of("a", "b"))
    end

    it "distinguishes field order" do
      digest_of("a", "b").should_not eq(digest_of("b", "a"))
    end

    it "distinguishes an empty field from a missing one" do
      digest_of("a", "", "b").should_not eq(digest_of("a", "b"))
    end

    it "distinguishes differing counts of empty fields" do
      digest_of("", "").should_not eq(digest_of(""))
    end

    # A value that itself looks like the framing must not be able to forge a
    # boundary.
    it "cannot be spoofed by a value containing the delimiter" do
      digest_of("1:x").should_not eq(digest_of("x"))
      digest_of("2:ab", "c").should_not eq(digest_of("ab", "c"))
    end

    it "handles multi-byte values by byte length, not char count" do
      # "한" is 3 bytes, 1 char; the prefix must use bytesize so a 3-char
      # ASCII value cannot collide with it.
      digest_of("한").should_not eq(digest_of("abc"))
    end

    it "keeps non-ASCII values distinct" do
      digest_of("한글").should_not eq(digest_of("한국"))
    end

    it "returns nil and mutates the digest in place" do
      digest = Digest::SHA256.new
      Hwaro::Utils::DigestUtils.update_length_prefixed(digest, "x").should be_nil
      digest.hexfinal.should eq(digest_of("x"))
    end

    it "accepts any ::Digest implementation" do
      digest = Digest::MD5.new
      Hwaro::Utils::DigestUtils.update_length_prefixed(digest, "x")
      digest.hexfinal.size.should eq(32)
    end
  end

  # Subresource Integrity values are what browsers compare byte-for-byte
  # against the fetched asset; the MDN reference vector pins the encoding.
  describe ".sri" do
    it "returns sha384 in base64 with the algorithm prefix" do
      Hwaro::Utils::DigestUtils.sri("alert('Hello, world.');")
        .should eq("sha384-H8BRh8j48O9oYatfu5AZzq6A9RINhZO5H16dQZngK7T62em8MUt1FLm52t+eX6xO")
    end
  end

  describe ".sri_file" do
    it "hashes a file's bytes and returns nil for a missing file" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a.js")
        File.write(path, "alert('Hello, world.');")
        Hwaro::Utils::DigestUtils.sri_file(path).should eq(Hwaro::Utils::DigestUtils.sri("alert('Hello, world.');"))
        Hwaro::Utils::DigestUtils.sri_file(File.join(dir, "missing.js")).should be_nil
        Hwaro::Utils::DigestUtils.sri_file(dir).should be_nil
      end
    end
  end
end

describe Hwaro::Utils::SriCache do
  it "memoizes per path, mtime and size until cleared" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "a.css")
      File.write(path, "a{}")
      stamp = Time.utc(2020, 1, 1)
      File.utime(stamp, stamp, path)
      Hwaro::Utils::SriCache.clear
      Hwaro::Utils::SriCache.sri(path).should eq(Hwaro::Utils::DigestUtils.sri("a{}"))

      # Same size and mtime: served from the memo, the file is not re-read.
      File.write(path, "b{}")
      File.utime(stamp, stamp, path)
      Hwaro::Utils::SriCache.sri(path).should eq(Hwaro::Utils::DigestUtils.sri("a{}"))

      # A different size (or mtime) is a different key.
      File.write(path, "b{x}")
      Hwaro::Utils::SriCache.sri(path).should eq(Hwaro::Utils::DigestUtils.sri("b{x}"))
      Hwaro::Utils::SriCache.sri(File.join(dir, "missing.css")).should be_nil
      Hwaro::Utils::SriCache.clear
    end
  end

  it "reports files rewritten after their value was handed out" do
    Dir.mktmpdir do |dir|
      kept = File.join(dir, "kept.css")
      changed = File.join(dir, "changed.css")
      File.write(kept, "k{}")
      File.write(changed, "c{}")
      Hwaro::Utils::SriCache.clear
      Hwaro::Utils::SriCache.sri(kept)
      Hwaro::Utils::SriCache.sri(changed)
      File.write(changed, "c{color:red}")
      Hwaro::Utils::SriCache.stale.should eq([File.expand_path(changed)])
      Hwaro::Utils::SriCache.clear
      Hwaro::Utils::SriCache.stale.should be_empty
    end
  end
end
