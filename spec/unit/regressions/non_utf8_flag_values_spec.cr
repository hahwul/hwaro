require "../../spec_helper"
require "../../../src/cli/commands/serve_command"

module Hwaro
  module CLI
    module Commands
      class ServeCommand
        def test_parse_options_utf8(args : Array(String))
          parse_options(args)
        end
      end
    end
  end
end

# argv carries raw bytes, so a latin-1 terminal passes `caf\xE9` as is. Text
# flag values met a regex (title slug, tag split, size parse, header parse,
# ignore pattern) and PCRE2 raised "UTF-8 error": an unclassified exit 1 with
# no JSON envelope under --json. They are a usage error now.
describe "non-UTF-8 text flag values" do
  bad = String.new(Bytes[0x63, 0x61, 0x66, 0xE9])

  it "are a usage error naming the flag" do
    err = expect_raises(Hwaro::HwaroError) { Hwaro::CLI.utf8_flag!("--title", bad) }
    err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
    err.message.to_s.should contain("--title")
    err.message.to_s.valid_encoding?.should be_true
    Hwaro::CLI.utf8_flag!("--title", "café").should eq("café")
  end

  it "are rejected by hwaro new --title / --tags" do
    {["x.md", "-t", bad], ["x.md", "--tags", "a,#{bad}"]}.each do |args|
      err = expect_raises(Hwaro::HwaroError) { Hwaro::CLI::Commands::NewCommand.new.parse_options(args) }
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
    end
  end

  it "are rejected by build/serve --memory-limit and serve --header" do
    err = expect_raises(Hwaro::HwaroError) do
      Hwaro::CLI::Commands::BuildCommand.new.parse_options(["--stream", "--memory-limit", bad])
    end
    err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
    serve = Hwaro::CLI::Commands::ServeCommand.new
    expect_raises(Hwaro::HwaroError, /--memory-limit/) { serve.test_parse_options_utf8(["--memory-limit", bad]) }
    expect_raises(Hwaro::HwaroError, /--header/) { serve.test_parse_options_utf8(["--header", "X-A: #{bad}"]) }
  end

  it "are rejected by tool check-links --ignore-url" do
    Dir.mktmpdir do |dir|
      err = expect_raises(Hwaro::HwaroError) do
        Hwaro::CLI::Commands::Tool::DeadlinkCommand.new.run(["-c", dir, "--internal-only", "--ignore-url", bad])
      end
      err.code.should eq(Hwaro::Errors::HWARO_E_USAGE)
    end
  end
end
