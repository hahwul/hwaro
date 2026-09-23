require "../spec_helper"
require "../../src/services/server/server"

# Regression coverage for serve rebuilds that left output behind which a cold
# build of the same final source does not produce.
#
# Reopened for the private seams; names are prefixed so they can't collide
# with the shims other spec files install.
module Hwaro
  module Services
    class Server
      def orphan_builder : Hwaro::Core::Build::Builder
        @builder
      end

      def orphan_apply_changeset(changeset : ChangeSet, options : Config::Options::BuildOptions)
        apply_changeset(changeset, options)
      end
    end
  end
end

private def orphan_options : Hwaro::Config::Options::BuildOptions
  options = Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public",
    parallel: false,
    highlight: false,
  )
  options.serve_mode = true
  # What the watcher's rebuild options carry: rebuilds write over the
  # previous output instead of wiping it.
  options.preserve_output = true
  options
end

private def write_tagged_site
  File.write("config.toml", <<-TOML
    title = "Tagged"
    base_url = "https://example.com"

    [[taxonomies]]
    name = "tags"
    feed = true
    TOML
  )
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  File.write("templates/page.html", "<html><body>{{ page.title }}</body></html>")
  File.write("templates/taxonomy.html", "<html><body>index</body></html>")
  File.write("templates/taxonomy_term.html", "<html><body>term</body></html>")
  File.write("content/posts/keep.md", "---\ntitle: Keep\ntags: [shared]\n---\nkeep")
  File.write("content/posts/gone.md", "---\ntitle: Gone\ntags: [shared, lonely]\n---\ngone")
end

describe "serve orphaned outputs" do
  # Taxonomy term pages have no source file, so only the `--cache` Finalize
  # prune ever removed one — a plain `hwaro serve` kept serving `/tags/lonely/`
  # (and its feed) after the last post carrying the tag was deleted.
  it "removes a term page whose last post was deleted (full rebuild)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_tagged_site
        server = Hwaro::Services::Server.new
        options = orphan_options
        server.orphan_builder.run(options).should be_true
        File.exists?("public/tags/lonely/index.html").should be_true
        File.exists?("public/tags/lonely/rss.xml").should be_true

        File.delete("content/posts/gone.md")
        changeset = Hwaro::Services::ChangeSet.new(
          modified_content: [] of String, modified_templates: [] of String,
          modified_static: [] of String, added_files: [] of String,
          removed_files: ["content/posts/gone.md"], config_changed: false,
        )
        server.orphan_apply_changeset(changeset, options)

        Dir.exists?("public/tags/lonely").should be_false
        File.exists?("public/tags/shared/index.html").should be_true
        File.exists?("public/tags/index.html").should be_true
      end
    end
  end

  it "removes a term page an incremental edit re-tagged away" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_tagged_site
        server = Hwaro::Services::Server.new
        options = orphan_options
        server.orphan_builder.run(options).should be_true
        File.exists?("public/tags/lonely/index.html").should be_true

        File.write("content/posts/gone.md", "---\ntitle: Gone\ntags: [shared]\n---\ngone")
        server.orphan_builder.run_incremental(["content/posts/gone.md"], options).should be_true

        Dir.exists?("public/tags/lonely").should be_false
        File.exists?("public/tags/shared/index.html").should be_true
      end
    end
  end
end
