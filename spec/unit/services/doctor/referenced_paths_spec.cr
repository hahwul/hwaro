require "../../../spec_helper"
require "../../../../src/services/doctor"

private def lexer_doctor_issues(dir : String, highlight : String) : Array(Hwaro::Services::Issue)
  config_path = File.join(dir, "config.toml")
  File.write(config_path, %(title = "My Site"\nbase_url = "https://example.com"\n[highlight]\n#{highlight}\n))
  Hwaro::Services::Doctor.new(content_dir: File.join(dir, "content"), config_path: config_path).run
end

describe "doctor: [highlight] lexers_dir" do
  it "reports each grammar that does not parse, naming the file" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lexers"))
      File.write(File.join(dir, "lexers", "bad.xml"), "<lexer><config><name>X</name></config>\n<rules>\n")
      File.write(File.join(dir, "lexers", "ok.xml"),
        %(<lexer><config><name>Ok</name></config><rules><state name="root"><rule pattern="."><token type="Text"/></rule></state></rules></lexer>))

      issues = lexer_doctor_issues(dir, %(lexers_dir = "lexers")).select { |i| i.id == "highlight-lexer-invalid" }
      issues.size.should eq(1)
      issues[0].level.should eq(:warning)
      issues[0].file.should eq(File.join(dir, "lexers", "bad.xml"))
      issues[0].message.should contain("invalid XML")
    end
  end

  it "reads an absolute lexers_dir as is" do
    Dir.mktmpdir do |dir|
      Dir.mktmpdir do |grammars|
        File.write(File.join(grammars, "bad.xml"), "<nope")
        issues = lexer_doctor_issues(dir, %(lexers_dir = #{grammars.inspect}))
        issues.any? { |i| i.id == "config-dir-missing" }.should be_false
        issues.select { |i| i.id == "highlight-lexer-invalid" }.map(&.file).should eq([File.join(grammars, "bad.xml")])
      end
    end
  end

  it "reports undefined state references and duplicate names like the build" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lexers"))
      ok = %(<lexer><config><name>Ok</name></config><rules><state name="root"><rule pattern="."><token type="Text"/></rule></state></rules></lexer>)
      File.write(File.join(dir, "lexers", "a.xml"), ok)
      File.write(File.join(dir, "lexers", "b.xml"), ok)
      File.write(File.join(dir, "lexers", "c.xml"),
        %(<lexer><config><name>C</name></config><rules><state name="root"><rule pattern="x"><push state="nope"/></rule></state></rules></lexer>))

      messages = lexer_doctor_issues(dir, %(lexers_dir = "lexers")).select { |i| i.id == "highlight-lexer-invalid" }.map(&.message)
      messages.should eq([
        %(syntax grammar not loaded — <push> names undefined state "nope"),
        "syntax grammar 'ok' is already defined by #{File.join(dir, "lexers", "a.xml")}; keeping #{File.join(dir, "lexers", "a.xml")}",
      ])
    end
  end

  it "reports a missing directory" do
    Dir.mktmpdir do |dir|
      issue = lexer_doctor_issues(dir, %(lexers_dir = "lexers")).find { |i| i.id == "config-dir-missing" }
      issue.should_not be_nil
      issue.not_nil!.message.should contain("[highlight] lexers_dir: lexers")
    end
  end

  it "says nothing in client mode or without the setting" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lexers"))
      File.write(File.join(dir, "lexers", "bad.xml"), "<nope")
      [%(mode = "client"\nlexers_dir = "lexers"), %(mode = "server")].each do |highlight|
        lexer_doctor_issues(dir, highlight).any? { |i| i.id == "highlight-lexer-invalid" || i.message.includes?("lexers_dir") }.should be_false
      end
    end
  end
end
