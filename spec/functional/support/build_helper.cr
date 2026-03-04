require "../../spec_helper"

# =============================================================================
# Shared helper for functional tests.
#
# Sets up a minimal project skeleton in a temp directory, runs Builder#run,
# and yields the temp dir so the caller can assert on files.
# =============================================================================

def build_site(
  config_toml : String,
  content_files : Hash(String, String) = {} of String => String,
  template_files : Hash(String, String) = {} of String => String,
  static_files : Hash(String, String) = {} of String => String,
  data_files : Hash(String, String) = {} of String => String,
  output_dir : String = "public",
  drafts : Bool = false,
  minify : Bool = false,
  highlight : Bool = false,
  cache : Bool = false,
  &
)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      # config
      File.write("config.toml", config_toml)

      # content
      content_files.each do |path, body|
        full = File.join("content", path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, body)
      end

      # templates
      template_files.each do |path, body|
        full = File.join("templates", path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, body)
      end

      # static
      static_files.each do |path, body|
        full = File.join("static", path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, body)
      end

      # data
      data_files.each do |path, body|
        full = File.join("data", path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, body)
      end

      builder = Hwaro::Core::Build::Builder.new

      # Register all content hooks (markdown, SEO, taxonomy)
      Hwaro::Content::Hooks.all.each do |hookable|
        builder.register(hookable)
      end

      builder.run(
        output_dir: output_dir,
        drafts: drafts,
        minify: minify,
        parallel: false,
        cache: cache,
        highlight: highlight,
        verbose: false,
        profile: false,
      )

      yield dir
    end
  end
end

# Minimal config used by most tests
BASIC_CONFIG = <<-TOML
title = "Test Site"
base_url = "http://localhost"
TOML
