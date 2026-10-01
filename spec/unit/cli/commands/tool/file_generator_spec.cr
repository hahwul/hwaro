require "../../../../spec_helper"

# `FileGenerator.emit` is the write tail shared by `tool platform` and
# `tool ci`.
describe Hwaro::CLI::Commands::Tool::FileGenerator do
  describe ".emit" do
    # Regression: a write failure escaped as an unhandled File::Error
    # (`Error: Error opening file with mode 'w': …`, exit 1) instead of a
    # classified error.
    it "reports a directory destination as a classified IO error" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          Dir.mkdir("out")
          err = expect_raises(Hwaro::HwaroError) do
            Hwaro::CLI::Commands::Tool::FileGenerator.emit("out", "x", false, true)
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_IO)
        end
      end
    end

    it "rejects an empty output path as a usage error" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          err = expect_raises(Hwaro::HwaroError) do
            Hwaro::CLI::Commands::Tool::FileGenerator.emit("", "x", false, true)
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
        end
      end
    end

    it "reports an unwritable destination as a classified IO error" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("blocker", "file, not a directory")
          err = expect_raises(Hwaro::HwaroError) do
            Hwaro::CLI::Commands::Tool::FileGenerator.emit("blocker/netlify.toml", "x", false, false)
          end
          err.code.should eq(Hwaro::Errors::HWARO_E_IO)
        end
      end
    end

    # Regression: a checked-out `netlify.toml -> <outside>` link was written
    # straight through — with no prompt at all when the link dangled.
    it "refuses to write through a dangling symlink that resolves outside the project" do
      Dir.mktmpdir do |outside|
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            victim = File.join(outside, "victim.toml")
            File.symlink(victim, "netlify.toml")
            expect_raises(Hwaro::HwaroError, /symlink/) do
              Hwaro::CLI::Commands::Tool::FileGenerator.emit("netlify.toml", "x", false, false)
            end
            File.exists?(victim).should be_false
          end
        end
      end
    end

    it "refuses to overwrite a file outside the project through a symlink, even with --force" do
      Dir.mktmpdir do |outside|
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            victim = File.join(outside, "victim.toml")
            File.write(victim, "precious")
            File.symlink(victim, "netlify.toml")
            expect_raises(Hwaro::HwaroError, /symlink/) do
              Hwaro::CLI::Commands::Tool::FileGenerator.emit("netlify.toml", "x", false, true)
            end
            File.read(victim).should eq("precious")
          end
        end
      end
    end

    it "refuses a symlinked parent directory that leaves the project" do
      Dir.mktmpdir do |outside|
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            File.symlink(outside, ".github")
            expect_raises(Hwaro::HwaroError, /symlink/) do
              Hwaro::CLI::Commands::Tool::FileGenerator.emit(".github/workflows/deploy.yml", "x", false, false)
            end
            File.exists?(File.join(outside, "workflows", "deploy.yml")).should be_false
          end
        end
      end
    end

    it "still writes through a symlink that stays inside the project, and to an explicit outside path" do
      Dir.mktmpdir do |outside|
        Dir.mktmpdir do |dir|
          Dir.cd(dir) do
            Dir.mkdir("deploy")
            File.symlink("deploy/netlify.toml", "netlify.toml")
            with_captured_log do
              Hwaro::CLI::Commands::Tool::FileGenerator.emit("netlify.toml", "inside", false, false)
            end
            File.read(File.join("deploy", "netlify.toml")).should eq("inside")

            explicit = File.join(outside, "netlify.toml")
            with_captured_log do
              Hwaro::CLI::Commands::Tool::FileGenerator.emit(explicit, "outside", false, false)
            end
            File.read(explicit).should eq("outside")
          end
        end
      end
    end
  end
end
