require "./support/build_helper"

# End-to-end coverage for static-file publishing. These run a full build via
# Builder#run so they exercise the same path the GitHub Action takes — most
# importantly the cached path (`cache: true`), where `.well-known/` used to be
# dropped (issue #610) and where OS/VCS cruft should be filtered (#611).
describe "Build: static file publishing" do
  {true, false}.each do |cache|
    mode = cache ? "cached" : "cold"

    it "publishes .well-known and filters cruft in a #{mode} build" do
      build_site(
        BASIC_CONFIG,
        content_files: {"index.md" => "---\ntitle: Home\n---\nHi"},
        template_files: {"page.html" => "{{ content }}"},
        static_files: {
          ".well-known/security.txt" => "Contact: mailto:x@y.z",
          ".well-known/humans.txt"   => "HAHWUL",
          "robots.txt"               => "User-agent: *",
          ".DS_Store"                => "junk",
          "css/.DS_Store"            => "junk",
          ".git/config"              => "[core]",
        },
        cache: cache,
      ) do
        # Legitimate dot-paths are published.
        File.exists?("public/.well-known/security.txt").should be_true
        File.read("public/.well-known/security.txt").should eq("Contact: mailto:x@y.z")
        File.exists?("public/.well-known/humans.txt").should be_true
        File.exists?("public/robots.txt").should be_true

        # Cruft is filtered out.
        File.exists?("public/.DS_Store").should be_false
        File.exists?("public/css/.DS_Store").should be_false
        File.exists?("public/.git/config").should be_false
      end
    end
  end

  it "respects a custom [static] exclude in a cached build" do
    config = <<-TOML
      title = "Test Site"
      base_url = "http://localhost"

      [static]
      exclude = ["*.bak"]
      TOML

    build_site(
      config,
      content_files: {"index.md" => "---\ntitle: Home\n---\nHi"},
      template_files: {"page.html" => "{{ content }}"},
      static_files: {
        "keep.txt"   => "keep",
        "secret.bak" => "drop",
      },
      cache: true,
    ) do
      File.exists?("public/keep.txt").should be_true
      File.exists?("public/secret.bak").should be_false
    end
  end
end
