require "../../../spec_helper"
require "../../../../src/content/hooks/image_variant_stamps"

# Forget the in-memory copy so the next call reads the log again, as a new
# process would.
module Hwaro::Content::Hooks::ImageVariantStamps
  def forget_loaded : Nil
    @@mutex.synchronize { @@stamps.clear }
  end
end

describe Hwaro::Content::Hooks::ImageVariantStamps do
  stamps = Hwaro::Content::Hooks::ImageVariantStamps

  it "fingerprints the exact mtime, size and settings of a source" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "a.png")
      File.write(path, "abc")
      File.touch(path, Time.utc(2020, 1, 1))
      stamps.fingerprint(path, "q85").should eq("1577836800000:3:q85")
      stamps.fingerprint(File.join(dir, "missing.png"), "q85").should be_nil
    end
  end

  it "persists stamps in .hwaro and ignores unreadable log lines" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        stamps.fresh?("public/a_320w.png", "fp1").should be_false
        stamps.record("public/a_320w.png", "fp1")
        stamps.fresh?("public/a_320w.png", "fp1").should be_true
        stamps.fresh?("public/a_320w.png", "fp2").should be_false

        File.exists?(".hwaro/.gitignore").should be_true
        File.open(".hwaro/image_variants.log", "a") { |io| io.puts "not json"; io.puts "[1,2]" }
        stamps.record("public/b_320w.png", "fp3")
        stamps.forget_loaded

        stamps.fresh?("public/a_320w.png", "fp1").should be_true
        stamps.fresh?("public/b_320w.png", "fp3").should be_true
        stamps.forget_loaded
      end
    end
  end

  it "rewrites a log that has outgrown its live entries" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        Dir.mkdir_p(".hwaro")
        File.open(".hwaro/image_variants.log", "w") do |io|
          400.times { |i| io.puts ["public/a.png", "fp#{i}"].to_json }
        end
        stamps.forget_loaded

        stamps.fresh?("public/a.png", "fp399").should be_true
        File.read_lines(".hwaro/image_variants.log").size.should eq(1)
        stamps.forget_loaded
      end
    end
  end
end
