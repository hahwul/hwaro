require "../../../spec_helper"
require "compress/gzip"
require "../../../../src/services/deployer"
require "../../../../src/models/config"
require "../../../../src/config/options/deploy_options"

class Hwaro::Services::Deployer
  def test_metadata_upload_argv(url : String, file : String, rel : String, matcher : Hwaro::Models::DeploymentMatcher) : Array(String)
    metadata_upload_argv(url, file, rel, matcher)
  end

  def test_metadata_matcher(rel : String, deployment : Hwaro::Models::DeploymentConfig, src_rel : String = rel) : Hwaro::Models::DeploymentMatcher?
    metadata_matcher(rel, compile_matchers(deployment), src_rel)
  end

  def test_metadata_percent_warning(url : String, source_dir : String, deployment : Hwaro::Models::DeploymentConfig) : String?
    metadata_percent_warning(url, metadata_uploads(url, source_dir, compile_matchers(deployment)))
  end

  def test_shell_join(argv : Array(String)) : String
    shell_join(argv)
  end
end

private def deploy_matcher(pattern : String, cache_control : String? = nil, content_type : String? = nil, gzip : Bool? = nil, force : Bool = false) : Hwaro::Models::DeploymentMatcher
  matcher = Hwaro::Models::DeploymentMatcher.new
  matcher.pattern = pattern
  matcher.cache_control = cache_control
  matcher.content_type = content_type
  matcher.gzip = gzip unless gzip.nil?
  matcher.force = force
  matcher
end

private def matcher_config(url : String, matchers : Array(Hwaro::Models::DeploymentMatcher), name : String = "t") : Hwaro::Models::Config
  config = Hwaro::Models::Config.new
  target = Hwaro::Models::DeploymentTarget.new
  target.name = name
  target.url = url
  config.deployment.targets << target
  config.deployment.matchers.concat(matchers)
  config
end

private def gunzip(path : String) : String
  File.open(path, "rb") { |file| Compress::Gzip::Reader.open(file, &.gets_to_end) }
end

describe "Deployer matchers" do
  describe "#metadata_upload_argv" do
    deployer = Hwaro::Services::Deployer.new
    full = deploy_matcher("x", cache_control: "public, max-age=60", content_type: "text/html; charset=utf-8", gzip: true)

    it "builds an aws s3 cp with every header" do
      deployer.test_metadata_upload_argv("s3://bkt/pre/", "/tmp/a b.html", "dir/a b.html", full).should eq([
        "aws", "s3", "cp", "/tmp/a b.html", "s3://bkt/pre/dir/a b.html",
        "--cache-control", "public, max-age=60",
        "--content-type", "text/html; charset=utf-8",
        "--content-encoding", "gzip",
      ])
    end

    it "builds a gsutil cp with -h headers and -Z for gzip" do
      deployer.test_metadata_upload_argv("gs://bkt", "/src/a.css", "a.css", full).should eq([
        "gsutil", "-h", "Cache-Control:public, max-age=60", "-h", "Content-Type:text/html; charset=utf-8",
        "cp", "-Z", "/src/a.css", "gs://bkt/a.css",
      ])
    end

    it "builds an az blob upload under the container prefix" do
      deployer.test_metadata_upload_argv("az://site/sub%20dir", "/src/a.css", "css/a.css", full).should eq([
        "az", "storage", "blob", "upload", "--container-name", "site",
        "--file", "/src/a.css", "--name", "sub dir/css/a.css", "--overwrite",
        "--content-cache-control", "public, max-age=60",
        "--content-type", "text/html; charset=utf-8",
        "--content-encoding", "gzip",
      ])
    end

    it "omits flags a matcher does not set" do
      only_cc = deploy_matcher("x", cache_control: "no-cache")
      deployer.test_metadata_upload_argv("s3://bkt", "/f", "f", only_cc).should eq(["aws", "s3", "cp", "/f", "s3://bkt/f", "--cache-control", "no-cache"])
      deployer.test_metadata_upload_argv("gs://bkt", "/f", "f", only_cc).should eq(["gsutil", "-h", "Cache-Control:no-cache", "cp", "/f", "gs://bkt/f"])
    end

    it "shell-escapes every argument but the program name" do
      posix_only!("single-quote shell escaping")
      deployer.test_shell_join(["aws", "s3", "cp", "/tmp/it's.html"]).should eq("aws 's3' 'cp' '/tmp/it'\\''s.html'")
    end
  end

  describe "#metadata_matcher" do
    it "picks the first metadata matcher in config order, unmerged" do
      config = matcher_config("s3://b", [
        deploy_matcher("\\.html$", force: true),
        deploy_matcher("\\.html$", cache_control: "no-cache"),
        deploy_matcher(".*", content_type: "text/plain", gzip: true),
      ])
      deployer = Hwaro::Services::Deployer.new
      html = deployer.test_metadata_matcher("index.html", config.deployment).not_nil!
      html.cache_control.should eq("no-cache")
      html.content_type.should be_nil
      html.gzip.should_not be_true
      deployer.test_metadata_matcher("a.css", config.deployment).not_nil!.content_type.should eq("text/plain")
    end

    it "also matches the source spelling of a stripped page" do
      config = matcher_config("s3://b", [deploy_matcher("\\.html$", gzip: true)])
      Hwaro::Services::Deployer.new.test_metadata_matcher("blog", config.deployment, "blog/index.html").should_not be_nil
    end
  end

  describe "cloud plan" do
    it "lists a metadata upload with headers for each matched file" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "index.html"), "<p>")
        Dir.mkdir(File.join(dir, "css"))
        File.write(File.join(dir, "css", "a.css"), "b{}")
        File.write(File.join(dir, "robots.txt"), "x")
        config = matcher_config("s3://bkt", [
          deploy_matcher("\\.html$", cache_control: "no-cache", gzip: true),
          deploy_matcher("\\.css$", cache_control: "max-age=31536000", content_type: "text/css"),
        ])
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: dir, targets: ["t"], dry_run: true)
        ops = Hwaro::Services::Deployer.new.plan(options, config)

        ops.map(&.action).should eq(["command", "upload", "upload"])
        css, html = ops[1], ops[2]
        css.path.should eq("css/a.css")
        css.destination.should eq("s3://bkt/css/a.css")
        css.headers.should eq({"Cache-Control" => "max-age=31536000", "Content-Type" => "text/css"})
        html.headers.should eq({"Cache-Control" => "no-cache", "Content-Encoding" => "gzip"})
        JSON.parse(ops.to_json)[1]["headers"]["Content-Type"].as_s.should eq("text/css")
      end
    end

    it "keeps the plan JSON shape without metadata matchers" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "index.html"), "<p>")
        config = matcher_config("s3://bkt", [deploy_matcher("\\.html$", force: true)])
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: dir, targets: ["t"], dry_run: true)
        ops = Hwaro::Services::Deployer.new.plan(options, config)
        ops.size.should eq(1)
        JSON.parse(ops.to_json)[0].as_h.keys.should eq(%w[target action path source destination])
      end
    end

    it "does not apply matchers to a custom command target, and warns" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "index.html"), "<p>")
        config = matcher_config("s3://bkt", [deploy_matcher("\\.html$", cache_control: "no-cache")])
        config.deployment.targets[0].command = "echo {source}"
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: dir, targets: ["t"], dry_run: true)
        ops = [] of Hwaro::Services::Deployer::PlannedOp
        log = with_captured_log { ops = Hwaro::Services::Deployer.new.plan(options, config) }
        ops.map(&.action).should eq(["command"])
        log.should contain("not applied to command target 't'")
      end
    end

    it "uploads each matched file through the CLI after the sync" do
      posix_only!("fake `aws` is a sh script on PATH")
      Dir.mktmpdir do |dir|
        src = File.join(dir, "public")
        bin = File.join(dir, "bin")
        capture = File.join(dir, "capture")
        log = File.join(dir, "argv.log")
        Dir.mkdir_p(src)
        Dir.mkdir_p(bin)
        Dir.mkdir_p(capture)
        File.write(File.join(src, "index.html"), "<h1>hello</h1>")
        File.write(File.join(src, "a.css"), "b{}")
        fake = File.join(bin, "aws")
        File.write(fake, <<-SH)
          #!/bin/sh
          for a in "$@"; do printf '[%s]' "$a"; done >> '#{log}'
          echo >> '#{log}'
          if [ "$2" = "cp" ]; then cp "$3" '#{capture}'/"$(basename "$3")"; fi
          SH
        File.chmod(fake, 0o755)

        config = matcher_config("s3://bkt", [deploy_matcher("\\.html$", cache_control: "no-cache", content_type: "text/html", gzip: true)])
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"])
        old_path = ENV["PATH"]
        begin
          ENV["PATH"] = "#{bin}:#{old_path}"
          with_captured_log { Hwaro::Services::Deployer.new.run(options, config).should be_true }
        ensure
          ENV["PATH"] = old_path
        end

        lines = File.read_lines(log)
        lines.size.should eq(2)
        lines[0].should start_with("[s3][sync]")
        lines[1].should match(/\A\[s3\]\[cp\]\[[^\]]+\/index\.html\]\[s3:\/\/bkt\/index\.html\]\[--cache-control\]\[no-cache\]\[--content-type\]\[text\/html\]\[--content-encoding\]\[gzip\]\z/)
        # The uploaded file is a gzip of the original, under its own name,
        # from a temp directory that is gone afterwards.
        uploaded = lines[1].match!(/\A\[s3\]\[cp\]\[([^\]]+)\]/)[1]
        uploaded.should_not eq(File.join(src, "index.html"))
        File.exists?(uploaded).should be_false
        gunzip(File.join(capture, "index.html")).should eq("<h1>hello</h1>")
      end
    end
  end

  describe "file:// gzip siblings" do
    it "writes a .gz next to each matched file, only when missing or stale" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "public")
        dest = File.join(dir, "out")
        Dir.mkdir_p(src)
        File.write(File.join(src, "index.html"), "v1")
        File.write(File.join(src, "a.css"), "b{}")
        config = matcher_config("file://#{dest}", [deploy_matcher("\\.html$", gzip: true)])
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"])
        deployer = Hwaro::Services::Deployer.new

        with_captured_log { deployer.run(options, config) }
        gunzip(File.join(dest, "index.html.gz")).should eq("v1")
        File.exists?(File.join(dest, "a.css.gz")).should be_false

        # Unchanged: nothing planned, the sibling survives the delete pass.
        ops = deployer.plan(Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"], dry_run: true), config)
        ops.should be_empty

        File.write(File.join(src, "index.html"), "v2")
        ops = deployer.plan(Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"], dry_run: true), config)
        ops.map { |op| {op.action, op.path} }.should eq([{"update", "index.html"}, {"gzip", "index.html.gz"}])
        with_captured_log { deployer.run(options, config) }
        gunzip(File.join(dest, "index.html.gz")).should eq("v2")
      end
    end

    it "lets a .gz the source ships win over a generated one" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "public")
        dest = File.join(dir, "out")
        Dir.mkdir_p(src)
        File.write(File.join(src, "index.html"), "page")
        File.write(File.join(src, "index.html.gz"), "authored")
        config = matcher_config("file://#{dest}", [deploy_matcher(".*", gzip: true)])
        with_captured_log { Hwaro::Services::Deployer.new.run(Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"]), config) }
        File.read(File.join(dest, "index.html.gz")).should eq("authored")
        File.exists?(File.join(dest, "index.html.gz.gz")).should be_false
      end
    end

    it "deletes a removed page's sibling without counting it against max_deletes" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "public")
        dest = File.join(dir, "out")
        Dir.mkdir_p(src)
        File.write(File.join(src, "index.html"), "home")
        File.write(File.join(src, "old.html"), "old")
        config = matcher_config("file://#{dest}", [deploy_matcher("\\.html$", gzip: true)])
        deployer = Hwaro::Services::Deployer.new
        with_captured_log { deployer.run(Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"]), config) }
        File.exists?(File.join(dest, "old.html.gz")).should be_true

        File.delete(File.join(src, "old.html"))
        with_captured_log { deployer.run(Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"], max_deletes: 1), config) }
        File.exists?(File.join(dest, "old.html")).should be_false
        File.exists?(File.join(dest, "old.html.gz")).should be_false
        File.exists?(File.join(dest, "index.html.gz")).should be_true
      end
    end

    it "warns that header matchers do nothing for a local target" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "public")
        Dir.mkdir_p(src)
        File.write(File.join(src, "index.html"), "x")
        config = matcher_config("file://#{File.join(dir, "out")}", [deploy_matcher("\\.html$", cache_control: "no-cache")])
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"], dry_run: true)
        log = with_captured_log { Hwaro::Services::Deployer.new.plan(options, config) }
        log.should contain("cache_control/content_type have no effect on local directory target 't'")
      end
    end
  end

  describe "review regressions" do
    it "counts unrelated X + X.gz pairs in full against max_deletes" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "public")
        dest = File.join(dir, "out")
        Dir.mkdir_p(src)
        Dir.mkdir_p(dest)
        File.write(File.join(src, "index.html"), "home")
        (1..4).each do |i|
          File.write(File.join(dest, "u#{i}.js"), "user")
          File.write(File.join(dest, "u#{i}.js.gz"), "user")
        end
        config = matcher_config("file://#{dest}", [deploy_matcher("\\.html$", gzip: true)])
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"], max_deletes: 4)
        err = expect_raises(Hwaro::HwaroError) { with_captured_log { Hwaro::Services::Deployer.new.run(options, config) } }
        (err.message || "").should contain("Refusing to delete 8 files")
        File.exists?(File.join(dest, "u1.js.gz")).should be_true
      end
    end

    it "clears a stale directory standing at X.gz before writing the sibling" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "public")
        dest = File.join(dir, "out")
        Dir.mkdir_p(src)
        Dir.mkdir_p(File.join(dest, "p.html.gz"))
        File.write(File.join(src, "p.html"), "page")
        File.write(File.join(dest, "p.html.gz", "old.txt"), "junk")
        config = matcher_config("file://#{dest}", [deploy_matcher("\\.html$", gzip: true)])
        with_captured_log { Hwaro::Services::Deployer.new.run(Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"]), config) }
        gunzip(File.join(dest, "p.html.gz")).should eq("page")
      end
    end

    it "never writes a sibling over a .gz the target excludes" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "public")
        dest = File.join(dir, "out")
        Dir.mkdir_p(src)
        Dir.mkdir_p(dest)
        File.write(File.join(src, "p.html"), "page")
        File.write(File.join(dest, "p.html.gz"), "hand")
        config = matcher_config("file://#{dest}", [deploy_matcher("\\.html$", gzip: true)])
        config.deployment.targets[0].exclude = "**/*.gz"
        with_captured_log { Hwaro::Services::Deployer.new.run(Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"]), config) }
        File.read(File.join(dest, "p.html.gz")).should eq("hand")
      end
    end

    it "lets gzip = false opt a path out of a later gzip matcher" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "public")
        dest = File.join(dir, "out")
        Dir.mkdir_p(src)
        File.write(File.join(src, "i.png"), "png")
        File.write(File.join(src, "p.html"), "page")
        config = load_config(<<-TOML)
          [[deployment.targets]]
          name = "t"
          url = "file://#{dest}"
          [[deployment.matchers]]
          pattern = '\\.png$'
          gzip = false
          [[deployment.matchers]]
          pattern = ".*"
          gzip = true
          TOML
        with_captured_log { Hwaro::Services::Deployer.new.run(Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"]), config) }
        File.exists?(File.join(dest, "i.png.gz")).should be_false
        File.exists?(File.join(dest, "p.html.gz")).should be_true
      end
    end

    it "skips gs:// metadata uploads for names gsutil would read as wildcards" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a[1].html"), "x")
        File.write(File.join(dir, "b.html"), "x")
        config = matcher_config("gs://bkt", [deploy_matcher("\\.html$", cache_control: "no-cache")])
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: dir, targets: ["t"], dry_run: true)
        ops = [] of Hwaro::Services::Deployer::PlannedOp
        log = with_captured_log { ops = Hwaro::Services::Deployer.new.plan(options, config) }
        ops.select(&.action.==("upload")).map(&.path).should eq(["b.html"])
        log.should contain("a[1].html")
      end
    end

    it "names the file whose '%' cmd.exe would expand" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "100%25off.html"), "x")
        File.write(File.join(dir, "plain.html"), "x")
        config = matcher_config("s3://bkt", [deploy_matcher("\\.html$", cache_control: "no-cache")])
        warning = Hwaro::Services::Deployer.new.test_metadata_percent_warning("s3://bkt", dir, config.deployment)
        warning.should_not be_nil
        warning.not_nil!.should contain("100%25off.html")
        File.delete(File.join(dir, "100%25off.html"))
        Hwaro::Services::Deployer.new.test_metadata_percent_warning("s3://bkt", dir, config.deployment).should be_nil
      end
    end
  end

  describe "re-review regressions" do
    ["empty", "holding only .DS_Store"].each do |shape|
      it "clears a directory at X.gz that is #{shape}" do
        Dir.mktmpdir do |dir|
          src = File.join(dir, "public")
          dest = File.join(dir, "out")
          Dir.mkdir_p(src)
          Dir.mkdir_p(File.join(dest, "p.html.gz"))
          File.write(File.join(dest, "p.html.gz", ".DS_Store"), "finder") if shape.includes?("DS_Store")
          File.write(File.join(src, "p.html"), "page")
          config = matcher_config("file://#{dest}", [deploy_matcher("\\.html$", gzip: true)])
          with_captured_log { Hwaro::Services::Deployer.new.run(Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"]), config) }
          gunzip(File.join(dest, "p.html.gz")).should eq("page")
        end
      end
    end

    it "refreshes a sibling before a delete pass that fails" do
      posix_only!("read-only directory blocks unlink")
      Dir.mktmpdir do |dir|
        src = File.join(dir, "public")
        dest = File.join(dir, "out")
        ro = File.join(dest, "ro")
        Dir.mkdir_p(src)
        File.write(File.join(src, "p.html"), "v1")
        config = matcher_config("file://#{dest}", [deploy_matcher("\\.html$", gzip: true)])
        deployer = Hwaro::Services::Deployer.new
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"])
        with_captured_log { deployer.run(options, config) }

        File.write(File.join(src, "p.html"), "v2")
        Dir.mkdir_p(ro)
        File.write(File.join(ro, "x"), "stale")
        File.chmod(ro, 0o555)
        begin
          pending!("running as root: a read-only directory does not block unlink") if File::Info.writable?(ro)
          expect_raises(Hwaro::HwaroError) { with_captured_log { deployer.run(options, config) } }
        ensure
          File.chmod(ro, 0o755)
        end
        File.read(File.join(dest, "p.html")).should eq("v2")
        gunzip(File.join(dest, "p.html.gz")).should eq("v2")
      end
    end

    it "exempts a removed stripped page's sibling, matched by its source spelling" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "public")
        dest = File.join(dir, "out")
        Dir.mkdir_p(File.join(src, "foo"))
        File.write(File.join(src, "index.html"), "home")
        File.write(File.join(src, "foo", "index.html"), "foo")
        config = matcher_config("file://#{dest}", [deploy_matcher("\\.html$", gzip: true)])
        config.deployment.targets[0].strip_index_html = true
        deployer = Hwaro::Services::Deployer.new
        with_captured_log { deployer.run(Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"]), config) }
        File.exists?(File.join(dest, "foo.gz")).should be_true

        FileUtils.rm_rf(File.join(src, "foo"))
        with_captured_log { deployer.run(Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"], max_deletes: 1), config) }
        File.exists?(File.join(dest, "foo")).should be_false
        File.exists?(File.join(dest, "foo.gz")).should be_false
      end
    end

    it "judges gsutil wildcards by the relative path and warns in sorted order" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "site[old]")
        Dir.mkdir_p(src)
        %w[q?.html b.html a[1].html].each { |name| File.write(File.join(src, name), "x") }
        config = matcher_config("gs://bkt", [deploy_matcher("\\.html$", cache_control: "no-cache")])
        options = Hwaro::Config::Options::DeployOptions.new(source_dir: src, targets: ["t"], dry_run: true)
        ops = [] of Hwaro::Services::Deployer::PlannedOp
        log = with_captured_log { ops = Hwaro::Services::Deployer.new.plan(options, config) }
        ops.select(&.action.==("upload")).map(&.path).should eq(["b.html"])
        a, q = log.index!("a[1].html"), log.index!("q?.html")
        (a < q).should be_true
      end
    end
  end
end
