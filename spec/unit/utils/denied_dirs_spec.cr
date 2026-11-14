require "../../spec_helper"

# ext/dir_denied_record.cr + Utils::DeniedDirs — Dir.glob skips an unreadable
# directory silently; the build must name it.
describe Hwaro::Utils::DeniedDirs do
  it "names a directory the glob could not open (warn) and fails for templates (fail_if_any)" do
    posix_only!("chmod-based permissions")
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("content/posts")
        File.write("content/posts/a.md", "x")
        File.chmod("content/posts", 0o000)
        begin
          next if File::Info.readable?("content/posts") # root reads it anyway
          Dir.glob("content/**/*").should_not contain("content/posts/a.md")
          log = with_captured_log { Hwaro::Utils::DeniedDirs.warn("content") }
          log.should contain("content/posts")
          log.should contain("permission denied")

          Dir.glob("content/**/*")
          err = expect_raises(Hwaro::HwaroError, /Cannot read directory content\/posts/) do
            Hwaro::Utils::DeniedDirs.fail_if_any("content")
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_IO)
        ensure
          File.chmod("content/posts", 0o755)
        end
      end
    end
  end
end
