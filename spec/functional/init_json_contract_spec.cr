require "../spec_helper"

# `hwaro init --json` used to print the human receipt (banner, create/exist
# tree, "created: N files") on stdout and emit no JSON at all, while its
# error path already emitted a machine payload. A scripted caller therefore
# got an unparseable stream on success. `run` writes straight to STDOUT and
# `--json` has to take effect before option parsing, so these drive the real
# binary rather than the command object.
private HWARO_BIN = File.expand_path("../../bin/hwaro", __DIR__)

Spec.before_suite do
  unless File.exists?(HWARO_BIN) && File::Info.executable?(HWARO_BIN)
    raise "Binary #{HWARO_BIN} is missing or not executable. Run `shards build` first."
  end
end

private def init_run(dir : String, args : Array(String))
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Process.run(HWARO_BIN, args, chdir: dir, output: stdout, error: stderr)
  {status.exit_code, stdout.to_s, stderr.to_s}
end

describe "hwaro init --json" do
  it "emits a single parseable result document and no human output" do
    Dir.mktmpdir do |dir|
      code, doc, _ = init_run(dir, ["init", ".", "--json"])

      code.should eq(Hwaro::Errors::EXIT_SUCCESS)
      doc.should_not contain("hwaro: init")
      doc.should_not contain("created:")

      payload = JSON.parse(doc)
      payload["status"].as_s.should eq("ok")
      payload["path"].as_s.should eq(".")
      payload["scaffold"].as_s.should eq("simple")
      payload["files_created"].as_i.should be > 0
    end
  end

  it "reports the requested scaffold" do
    Dir.mktmpdir do |dir|
      _, doc, _ = init_run(dir, ["init", ".", "-j", "--scaffold", "blog"])
      JSON.parse(doc)["scaffold"].as_s.should eq("blog")
    end
  end

  it "keeps the scaffold-list hint off stdout when --scaffold is unknown" do
    Dir.mktmpdir do |dir|
      # The invalid-scaffold path logs "Available scaffolds:" before raising;
      # with JSON mode enabled only after parsing, that human list shared
      # stdout with the JSON error payload.
      code, doc, _ = init_run(dir, ["init", ".", "--scaffold", "zzz", "--json"])

      code.should eq(Hwaro::Errors::EXIT_USAGE)
      doc.should_not contain("Available scaffolds:")
      JSON.parse(doc)["status"].as_s.should eq("error")
    end
  end

  it "still lists scaffolds as JSON with --list-scaffolds" do
    Dir.mktmpdir do |dir|
      _, doc, _ = init_run(dir, ["init", "--list-scaffolds", "--json"])
      names = JSON.parse(doc).as_a.map(&.["name"].as_s)
      names.should contain("simple")
      names.should contain("book")
    end
  end
end
