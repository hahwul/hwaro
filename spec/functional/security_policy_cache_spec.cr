require "../spec_helper"
require "../../src/core/build/builder"

describe "security policy cache migration" do
  it "re-renders pages from a cache written before the privacy policy change" do
    config = <<-TOML
      title = "Cache Policy"
      base_url = "https://example.com"

      [privacy]
      enabled = true
      TOML
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", config)
        FileUtils.mkdir_p(["content", "templates"])
        File.write("content/index.md", "---\ntitle: Home\n---\nFresh page")
        File.touch("content/index.md", Time.utc - 10.seconds)
        File.write("templates/index.html", "{{ content }}")

        2.times do |pass|
          builder = Hwaro::Core::Build::Builder.new
          Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
          builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", cache: true))
          next if pass == 1

          cache_path = ".hwaro_cache.json"
          cache = Hwaro::Core::Build::CacheData.from_json(File.read(cache_path))
          cache.metadata.config_hash = cache.metadata.config_hash.sub(/-security-policy:1\z/, "")
          File.write(cache_path, cache.to_json)
          File.write("public/index.html", "stale cached page")
        end

        File.read("public/index.html").should contain("Fresh page")
      end
    end
  end
end
