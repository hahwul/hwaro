require "../../spec_helper"
require "../../support/build_helper"

# A process killed between FileSafe's write and rename leaves a
# `hwaro-<pid>-<id>.tmp` beside its target. If that lands in a source tree
# (`tool convert` writes beside content files) the next build must not publish it.
describe "interrupted temp files in source trees" do
  it "are not published from static/, bundles or [content.files]" do
    build_site(
      %(title = "t"\nbase_url = "http://localhost"\n[content.files]\nallow_extensions = [".tmp", ".txt"]\n),
      content_files: {
        "post/index.md"          => "+++\ntitle = \"P\"\n+++\nbody",
        "post/hwaro-4242-7.tmp"  => "junk",
        "post/keep.txt"          => "ok",
        "hwaro-4242-7.tmp"       => "junk",
        "other/hwaro-4242-7.tmp" => "junk",
      },
      static_files: {"hwaro-4242-7.tmp" => "junk", "keep.txt" => "ok"},
    ) do |dir|
      Dir.glob(File.join(dir, "public", "**", "hwaro-*.tmp"), match: File::MatchOptions::DotFiles).should be_empty
      File.exists?(File.join(dir, "public", "keep.txt")).should be_true
      File.exists?(File.join(dir, "public", "post", "keep.txt")).should be_true
    end
  end
end
