require "../../../../spec_helper"

class Hwaro::CLI::Commands::Tool::DoctorCommand
  def render_human_for_test(issues : Array(Hwaro::Services::Issue)) : Nil
    render_human(issues, "config.toml", Set(String).new)
  end
end

private def missing_translation(n : Int32, code : String) : Hwaro::Services::Issue
  Hwaro::Services::Issue.new(id: "translation-missing", level: :info, category: "i18n",
    file: "content/p#{n.to_s.rjust(2, '0')}.md", message: "No '#{code}' translation", language: code)
end

describe Hwaro::CLI::Commands::Tool::DoctorCommand do
  it "shows the first 10 translation issues per language, then a count of the rest" do
    issues = (1..12).map { |n| missing_translation(n, "ko") } + [missing_translation(1, "ja")]
    output = with_captured_log { Hwaro::CLI::Commands::Tool::DoctorCommand.new.render_human_for_test(issues) }

    output.should contain("ko: 12 missing")
    output.should contain("content/p10.md")
    output.should_not contain("content/p11.md")
    output.should contain("… and 2 more (use --json for all)")
    output.should contain("ja: 1 missing")
    output.scan("more (use --json for all)").size.should eq(1)
  end
end
