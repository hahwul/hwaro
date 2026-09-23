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

  # Alias stubs and `/page/N/` files are recorded only in a page's `--cache`
  # entry, so without `--cache` nothing ever deleted the ones a later render
  # stopped writing — and incremental rebuilds skip the cache prune even with
  # it.
  it "removes an alias stub the page no longer declares (incremental)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_tagged_site
        File.write("content/posts/keep.md", "---\ntitle: Keep\naliases: [/old-keep/]\n---\nkeep")
        server = Hwaro::Services::Server.new
        options = orphan_options
        server.orphan_builder.run(options).should be_true
        File.exists?("public/old-keep/index.html").should be_true

        File.write("content/posts/keep.md", "---\ntitle: Keep\n---\nkeep")
        server.orphan_builder.run_incremental(["content/posts/keep.md"], options).should be_true

        Dir.exists?("public/old-keep").should be_false
        File.exists?("public/posts/keep/index.html").should be_true
      end
    end
  end

  it "removes the alias stubs of a deleted page (full rebuild)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_tagged_site
        File.write("content/posts/gone.md", "---\ntitle: Gone\naliases: [/old-gone/]\n---\ngone")
        server = Hwaro::Services::Server.new
        options = orphan_options
        server.orphan_builder.run(options).should be_true
        File.exists?("public/old-gone/index.html").should be_true

        File.delete("content/posts/gone.md")
        server.orphan_builder.run(options).should be_true

        Dir.exists?("public/old-gone").should be_false
      end
    end
  end

  it "keeps a stub another page takes over in the same rebuild" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_tagged_site
        File.write("content/posts/gone.md", "---\ntitle: Gone\naliases: [/moved/]\n---\ngone")
        server = Hwaro::Services::Server.new
        options = orphan_options
        server.orphan_builder.run(options).should be_true

        File.write("content/posts/gone.md", "---\ntitle: Gone\n---\ngone")
        File.write("content/posts/keep.md", "---\ntitle: Keep\naliases: [/moved/]\n---\nkeep")
        server.orphan_builder.run(options).should be_true

        File.read("public/moved/index.html").should contain("/posts/keep/")
      end
    end
  end

  it "removes a pagination page a shrinking section no longer fills" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_tagged_site
        File.write("content/posts/_index.md", "---\ntitle: Posts\npaginate: 1\n---\n")
        File.write("templates/section.html", "<html><body>{{ section.title }}</body></html>")
        server = Hwaro::Services::Server.new
        options = orphan_options
        server.orphan_builder.run(options).should be_true
        File.exists?("public/posts/page/2/index.html").should be_true

        File.write("content/posts/_index.md", "---\ntitle: Posts\npaginate: 5\n---\n")
        server.orphan_builder.run_incremental(["content/posts/_index.md"], options).should be_true

        Dir.exists?("public/posts/page/2").should be_false
        File.exists?("public/posts/index.html").should be_true
      end
    end
  end

  # Without `--cache` the claims diff that prunes source-less generated
  # outputs had nothing to diff against, so every CSS save in a serve session
  # left the previous fingerprinted bundle behind.
  it "drops a superseded fingerprinted bundle on a full rebuild" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_tagged_site
        File.open("config.toml", "a") do |io|
          io << "\n[assets]\nenabled = true\nfingerprint = true\n\n"
          io << "[[assets.bundles]]\nname = \"main.css\"\nfiles = [\"css/a.css\"]\n"
        end
        FileUtils.mkdir_p("static/css")
        File.write("static/css/a.css", "body{color:red}")
        server = Hwaro::Services::Server.new
        options = orphan_options
        server.orphan_builder.run(options).should be_true
        first = Dir.glob("public/assets/main.*.css")
        first.size.should eq(1)

        File.write("static/css/a.css", "body{color:blue}")
        server.orphan_builder.run(options).should be_true

        bundles = Dir.glob("public/assets/main.*.css")
        bundles.size.should eq(1)
        bundles.should_not eq(first)
      end
    end
  end

  it "drops the AMP tree once [amp] is switched off" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_tagged_site
        base = File.read("config.toml")
        File.write("config.toml", base + "\n[amp]\nenabled = true\nsections = [\"posts\"]\n")
        server = Hwaro::Services::Server.new
        options = orphan_options
        server.orphan_builder.run(options).should be_true
        File.exists?("public/amp/posts/keep/index.html").should be_true

        File.write("config.toml", base)
        server.orphan_builder.run(options).should be_true

        Dir.exists?("public/amp").should be_false
        File.exists?("public/posts/keep/index.html").should be_true
      end
    end
  end
end
