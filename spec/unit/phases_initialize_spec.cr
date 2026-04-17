require "../spec_helper"
require "../../src/core/build/builder"

# Reopen Builder to expose private Initialize-phase helpers for testing.
module Hwaro::Core::Build
  class Builder
    def test_setup_output_dir(output_dir : String, incremental : Bool = false)
      setup_output_dir(output_dir, incremental)
    end

    def test_copy_static_files(output_dir : String, verbose : Bool = false, incremental : Bool = false)
      copy_static_files(output_dir, verbose, incremental)
    end

    def test_load_templates : Hash(String, String)
      load_templates
    end

    def test_load_data_files(site : Models::Site)
      load_data_files(site)
    end

    def test_create_fresh_crinja_env : Crinja
      create_fresh_crinja_env
    end

    def test_run_initialize(ctx : Lifecycle::BuildContext, profiler : Profiler)
      execute_initialize_phase(ctx, profiler)
    end

    def test_set_config_for_init(config : Models::Config)
      @config = config
    end

    def test_get_site
      @site
    end

    def test_get_cache
      @cache
    end

    def test_get_templates
      @templates
    end
  end
end

describe Hwaro::Core::Build::Phases::Initialize do
  describe "#setup_output_dir" do
    it "creates the output directory when it does not exist" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          builder.test_setup_output_dir("public")
          Dir.exists?("public").should be_true
        end
      end
    end

    it "wipes the output directory in non-incremental mode" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("public")
          File.write("public/stale.html", "stale")

          builder = Hwaro::Core::Build::Builder.new
          builder.test_setup_output_dir("public", incremental: false)

          Dir.exists?("public").should be_true
          File.exists?("public/stale.html").should be_false
        end
      end
    end

    it "preserves existing files in incremental mode" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("public")
          File.write("public/keep.html", "keep")

          builder = Hwaro::Core::Build::Builder.new
          builder.test_setup_output_dir("public", incremental: true)

          File.exists?("public/keep.html").should be_true
        end
      end
    end
  end

  describe "#copy_static_files" do
    it "is a no-op when no static directory exists" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("public")
          builder = Hwaro::Core::Build::Builder.new
          builder.test_copy_static_files("public")
          # Nothing copied; directory still empty
          Dir.children("public").should be_empty
        end
      end
    end

    it "copies all files in non-incremental mode" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("static/css")
          File.write("static/robots.txt", "User-agent: *")
          File.write("static/css/main.css", "body{}")
          FileUtils.mkdir_p("public")

          builder = Hwaro::Core::Build::Builder.new
          builder.test_copy_static_files("public")

          File.exists?("public/robots.txt").should be_true
          File.exists?("public/css/main.css").should be_true
          File.read("public/robots.txt").should eq("User-agent: *")
        end
      end
    end

    it "skips unchanged files in incremental mode" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("static")
          File.write("static/a.txt", "src")

          FileUtils.mkdir_p("public")
          File.write("public/a.txt", "dest")
          # Make destination newer than source so the incremental copy skips it.
          newer = Time.utc + 1.hour
          File.utime(newer, newer, "public/a.txt")

          builder = Hwaro::Core::Build::Builder.new
          builder.test_copy_static_files("public", incremental: true)

          File.read("public/a.txt").should eq("dest")
        end
      end
    end

    it "copies new files in incremental mode" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("static")
          File.write("static/new.txt", "new content")
          FileUtils.mkdir_p("public")

          builder = Hwaro::Core::Build::Builder.new
          builder.test_copy_static_files("public", incremental: true)

          File.exists?("public/new.txt").should be_true
          File.read("public/new.txt").should eq("new content")
        end
      end
    end
  end

  describe "#load_templates" do
    it "returns an empty hash when no templates directory exists" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          templates = builder.test_load_templates
          templates.should be_empty
        end
      end
    end

    it "loads template files from the templates directory" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("templates")
          File.write("templates/page.html", "<p>{{ content }}</p>")
          File.write("templates/section.html", "<section>{{ content }}</section>")

          builder = Hwaro::Core::Build::Builder.new
          templates = builder.test_load_templates

          templates.has_key?("page").should be_true
          templates.has_key?("section").should be_true
          templates["page"].should contain("{{ content }}")
        end
      end
    end

    it "honors extension priority (html beats j2)" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("templates")
          File.write("templates/page.html", "from-html")
          File.write("templates/page.j2", "from-j2")

          builder = Hwaro::Core::Build::Builder.new
          templates = builder.test_load_templates

          templates["page"].should eq("from-html")
        end
      end
    end

    it "uses default template as fallback for page when no page template exists" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("templates")
          File.write("templates/default.html", "default-body")

          builder = Hwaro::Core::Build::Builder.new
          templates = builder.test_load_templates

          templates["page"]?.should eq("default-body")
        end
      end
    end
  end

  describe "#load_data_files" do
    it "loads YAML data files into site.data" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("data")
          File.write("data/people.yml", "alice: { age: 30 }\nbob: { age: 25 }\n")

          builder = Hwaro::Core::Build::Builder.new
          site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
          builder.test_load_data_files(site)

          site.data.has_key?("people").should be_true
        end
      end
    end

    it "loads JSON data files" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("data")
          File.write("data/menu.json", %({"home": "/"}))

          builder = Hwaro::Core::Build::Builder.new
          site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
          builder.test_load_data_files(site)

          site.data.has_key?("menu").should be_true
        end
      end
    end

    it "loads TOML data files" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("data")
          File.write("data/config.toml", %(title = "Hello"))

          builder = Hwaro::Core::Build::Builder.new
          site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
          builder.test_load_data_files(site)

          site.data.has_key?("config").should be_true
        end
      end
    end

    it "is a no-op when data directory does not exist" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
          # Pre-populate data to verify it is cleared
          site.data["seed"] = Crinja::Value.new("x")
          builder.test_load_data_files(site)
          site.data.should be_empty
        end
      end
    end

    it "skips invalid data files but keeps the build alive" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("data")
          File.write("data/bad.json", "not valid json")

          builder = Hwaro::Core::Build::Builder.new
          site = Hwaro::Models::Site.new(Hwaro::Models::Config.new)
          builder.test_load_data_files(site)

          site.data.has_key?("bad").should be_false
        end
      end
    end
  end

  describe "#create_fresh_crinja_env" do
    it "returns a Crinja instance" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          env = builder.test_create_fresh_crinja_env
          env.should be_a(Crinja)
        end
      end
    end

    it "returns a fresh instance per call" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          env_a = builder.test_create_fresh_crinja_env
          env_b = builder.test_create_fresh_crinja_env
          env_a.object_id.should_not eq(env_b.object_id)
        end
      end
    end
  end

  describe "#execute_initialize_phase" do
    it "initializes cache, site, and templates" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          FileUtils.mkdir_p("templates")
          File.write("templates/page.html", "{{ content }}")

          builder = Hwaro::Core::Build::Builder.new
          builder.test_set_config_for_init(Hwaro::Models::Config.new)

          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", cache: false)
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
          profiler = Hwaro::Profiler.new(enabled: false)

          result = builder.test_run_initialize(ctx, profiler)

          result.should eq(Hwaro::Core::Lifecycle::HookResult::Continue)
          builder.test_get_site.should_not be_nil
          builder.test_get_cache.should_not be_nil
          templates = builder.test_get_templates
          templates.should_not be_nil
          templates.not_nil!.has_key?("page").should be_true
          Dir.exists?("public").should be_true
        end
      end
    end

    it "applies base_url override from options" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          config = Hwaro::Models::Config.new
          config.base_url = "http://default.example"
          builder.test_set_config_for_init(config)

          options = Hwaro::Config::Options::BuildOptions.new(
            output_dir: "public",
            base_url: "http://override.example",
            cache: false,
          )
          ctx = Hwaro::Core::Lifecycle::BuildContext.new(options)
          profiler = Hwaro::Profiler.new(enabled: false)

          builder.test_run_initialize(ctx, profiler)

          ctx.config.not_nil!.base_url.should eq("http://override.example")
        end
      end
    end
  end
end
