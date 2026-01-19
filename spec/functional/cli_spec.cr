require "../spec_helper"
require "file_utils"

describe "CLI Commands" do
  describe Hwaro::CLI::CommandRegistry do
    # Initialize runner to register commands
    Hwaro::CLI::Runner.new

    it "has init command registered" do
      Hwaro::CLI::CommandRegistry.has?("init").should be_true
    end

    it "has build command registered" do
      Hwaro::CLI::CommandRegistry.has?("build").should be_true
    end

    it "has serve command registered" do
      Hwaro::CLI::CommandRegistry.has?("serve").should be_true
    end
  end

  describe "hwaro init" do
    it "creates project structure in specified directory" do
      temp_dir = File.tempname("hwaro_test")
      Dir.mkdir(temp_dir)
      begin
        project_dir = File.join(temp_dir, "test_site")
        Dir.mkdir(project_dir)

        # Run hwaro init
        output_io = IO::Memory.new
        error_io = IO::Memory.new
        status = Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["init", project_dir], output: output_io, error: error_io)
        output = output_io.to_s
        error = error_io.to_s

        status.success?.should be_true

        # Check if config.toml is created
        config_path = File.join(project_dir, "config.toml")
        File.exists?(config_path).should be_true

        # Check if content directory is created
        content_dir = File.join(project_dir, "content")
        Dir.exists?(content_dir).should be_true

        # Check if templates directory is created
        templates_dir = File.join(project_dir, "templates")
        Dir.exists?(templates_dir).should be_true

        # Check if index.md is created in content
        index_md = File.join(content_dir, "index.md")
        File.exists?(index_md).should be_true
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
      end
    end
  end

  describe "hwaro build" do
    it "builds the site successfully" do
      temp_dir = File.tempname("hwaro_test")
      Dir.mkdir(temp_dir)
      begin
        project_dir = File.join(temp_dir, "test_site")
        Dir.mkdir(project_dir)

        # Initialize project
        init_output_io = IO::Memory.new
        init_error_io = IO::Memory.new
        init_status = Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["init", project_dir], output: init_output_io, error: init_error_io)

        # Run hwaro build
        build_output_io = IO::Memory.new
        build_error_io = IO::Memory.new
        status = Process.run(File.expand_path("../../bin/hwaro", __DIR__), ["build"], chdir: project_dir, output: build_output_io, error: build_error_io)
        output = build_output_io.to_s
        error = build_error_io.to_s

        status.success?.should be_true

        # Check if public directory is created
        public_dir = File.join(project_dir, "public")
        Dir.exists?(public_dir).should be_true

        # Check if index.html is generated
        index_html = File.join(public_dir, "index.html")
        File.exists?(index_html).should be_true
      ensure
        FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
      end
    end
  end
end
