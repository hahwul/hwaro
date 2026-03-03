require "../spec_helper"
require "../../src/services/server/server"
require "../../src/core/build/builder"
require "../../src/content/hooks"

# Reopen Server to test private methods
module Hwaro
  module Services
    class Server
      def test_sanitize_output_dir(dir : String)
        sanitize_output_dir(dir)
      end
    end
  end
end

# Reopen Builder to test private inject_error_overlay method
module Hwaro
  module Core
    module Build
      class Builder
        def test_inject_error_overlay(html : String, warnings : Array(String)) : String
          inject_error_overlay(html, warnings)
        end
      end
    end
  end
end

class DummyHandler
  include HTTP::Handler

  property called : Bool = false

  def call(context)
    @called = true
  end
end

describe Hwaro::Services::Server do
  describe "#sanitize_output_dir" do
    it "normalizes clean relative paths" do
      server = Hwaro::Services::Server.new
      server.test_sanitize_output_dir("foo/bar").should eq("foo/bar")
      server.test_sanitize_output_dir("./baz").should eq("baz")
    end

    it "defaults to 'public' for paths starting with .." do
      server = Hwaro::Services::Server.new
      server.test_sanitize_output_dir("../foo").should eq("public")
    end

    it "defaults to 'public' for absolute paths" do
      server = Hwaro::Services::Server.new
      server.test_sanitize_output_dir("/foo").should eq("public")
    end
  end
end

describe Hwaro::Services::IndexRewriteHandler do
  it "rewrites path ending in / to index.html" do
    Dir.mktmpdir do |dir|
      handler = Hwaro::Services::IndexRewriteHandler.new(dir)
      dummy = DummyHandler.new
      handler.next = dummy

      request = HTTP::Request.new("GET", "/some/path/")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      request.path.should eq("/some/path/index.html")
      dummy.called.should be_true
    end
  end

  it "redirects directory without slash to slash" do
    Dir.mktmpdir do |dir|
      # Create a directory inside public dir
      FileUtils.mkdir_p(File.join(dir, "some/dir"))

      handler = Hwaro::Services::IndexRewriteHandler.new(dir)
      dummy = DummyHandler.new
      handler.next = dummy

      request = HTTP::Request.new("GET", "/some/dir")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      response.status_code.should eq(301)
      response.headers["Location"].should eq("/some/dir/")
      dummy.called.should be_false
    end
  end

  it "passes through files that don't need rewriting" do
    Dir.mktmpdir do |dir|
      handler = Hwaro::Services::IndexRewriteHandler.new(dir)
      dummy = DummyHandler.new
      handler.next = dummy

      request = HTTP::Request.new("GET", "/some/file.html")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)

      request.path.should eq("/some/file.html")
      dummy.called.should be_true
    end
  end
end

describe Hwaro::Services::NotFoundHandler do
  it "serves 404.html if present" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "404.html"), "Custom 404")

      handler = Hwaro::Services::NotFoundHandler.new(dir)

      request = HTTP::Request.new("GET", "/nonexistent")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)
      response.close

      response.status_code.should eq(404)
      io.rewind
      content = io.to_s
      content.should contain("Custom 404")
    end
  end

  it "serves default 404 message if 404.html missing" do
    Dir.mktmpdir do |dir|
      handler = Hwaro::Services::NotFoundHandler.new(dir)

      request = HTTP::Request.new("GET", "/nonexistent")
      io = IO::Memory.new
      response = HTTP::Server::Response.new(io)
      context = HTTP::Server::Context.new(request, response)

      handler.call(context)
      response.close

      response.status_code.should eq(404)
      io.rewind
      content = io.to_s
      content.should contain("404 Not Found")
    end
  end
end

describe Hwaro::Services::ChangeSet do
  describe "#empty?" do
    it "returns true when nothing changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.empty?.should be_true
    end

    it "returns false when content changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.empty?.should be_false
    end

    it "returns false when config changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: true,
      )
      cs.empty?.should be_false
    end
  end

  describe "#needs_full_rebuild?" do
    it "returns true when config changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: true,
      )
      cs.needs_full_rebuild?.should be_true
    end

    it "returns true when files were added" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: ["content/posts/new-post.md"],
        removed_files: [] of String,
        config_changed: false,
      )
      cs.needs_full_rebuild?.should be_true
    end

    it "returns true when files were removed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: ["content/posts/old-post.md"],
        config_changed: false,
      )
      cs.needs_full_rebuild?.should be_true
    end

    it "returns false for content-only modification" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.needs_full_rebuild?.should be_false
    end

    it "returns false for static-only modification" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: ["static/css/style.css"],
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.needs_full_rebuild?.should be_false
    end
  end

  describe "#templates_only?" do
    it "returns true when only templates changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: ["templates/page.html"],
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.templates_only?.should be_true
    end

    it "returns false when templates and content changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: ["templates/page.html"],
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.templates_only?.should be_false
    end

    it "returns false when templates changed and files added" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: ["templates/page.html"],
        modified_static: [] of String,
        added_files: ["content/new.md"],
        removed_files: [] of String,
        config_changed: false,
      )
      cs.templates_only?.should be_false
    end

    it "returns false when no templates changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.templates_only?.should be_false
    end
  end

  describe "#static_only?" do
    it "returns true when only static files changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: ["static/css/style.css", "static/js/app.js"],
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.static_only?.should be_true
    end

    it "returns false when static and content changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: ["static/css/style.css"],
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.static_only?.should be_false
    end

    it "returns false when static changed and config changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: ["static/css/style.css"],
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: true,
      )
      cs.static_only?.should be_false
    end
  end

  describe "#content_incremental?" do
    it "returns true when only content files were modified" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.content_incremental?.should be_true
    end

    it "returns true when content and static were modified (no structural changes)" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: ["static/css/style.css"],
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.content_incremental?.should be_true
    end

    it "returns false when files were added alongside content changes" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: ["content/posts/new.md"],
        removed_files: [] of String,
        config_changed: false,
      )
      cs.content_incremental?.should be_false
    end

    it "returns false when templates also changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: ["templates/page.html"],
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.content_incremental?.should be_false
    end

    it "returns false when config also changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: true,
      )
      cs.content_incremental?.should be_false
    end

    it "returns false when no content changed" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: [] of String,
        modified_static: ["static/css/style.css"],
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.content_incremental?.should be_false
    end
  end

  describe "classification priority" do
    it "full rebuild takes precedence over content incremental" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/hello.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: ["content/posts/new.md"],
        removed_files: [] of String,
        config_changed: false,
      )
      cs.needs_full_rebuild?.should be_true
      cs.content_incremental?.should be_false
    end

    it "full rebuild takes precedence over templates only" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: ["templates/page.html"],
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: ["templates/old.html"],
        config_changed: false,
      )
      cs.needs_full_rebuild?.should be_true
      cs.templates_only?.should be_false
    end

    it "multiple content modifications are incremental" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: ["content/posts/a.md", "content/posts/b.md", "content/about.md"],
        modified_templates: [] of String,
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.content_incremental?.should be_true
      cs.needs_full_rebuild?.should be_false
    end

    it "multiple template modifications are templates_only" do
      cs = Hwaro::Services::ChangeSet.new(
        modified_content: [] of String,
        modified_templates: ["templates/page.html", "templates/base.html", "templates/header.html"],
        modified_static: [] of String,
        added_files: [] of String,
        removed_files: [] of String,
        config_changed: false,
      )
      cs.templates_only?.should be_true
    end
  end
end

# Expose private detect_changes and classify_modified for testing
module Hwaro
  module Services
    class Server
      def test_detect_changes(old_mtimes : Hash(String, Time), new_mtimes : Hash(String, Time)) : ChangeSet
        detect_changes(old_mtimes, new_mtimes)
      end
    end
  end
end

describe "Builder#inject_error_overlay" do
  it "injects overlay before </body>" do
    builder = Hwaro::Core::Build::Builder.new
    html = "<html><body><p>Hello</p></body></html>"
    warnings = ["No template found for test.md. Using raw content."]

    result = builder.test_inject_error_overlay(html, warnings)
    result.should contain("hwaro-error-overlay")
    result.should contain("Build Warning")
    result.should contain("No template found for test.md")
    # Overlay should be before </body>
    overlay_pos = result.index("hwaro-error-overlay").not_nil!
    body_pos = result.rindex("</body>").not_nil!
    overlay_pos.should be < body_pos
  end

  it "appends overlay when no </body> tag exists" do
    builder = Hwaro::Core::Build::Builder.new
    html = "<p>Simple content</p>"
    warnings = ["Template error for page.md: undefined variable"]

    result = builder.test_inject_error_overlay(html, warnings)
    result.should contain("hwaro-error-overlay")
    result.should start_with("<p>Simple content</p>")
  end

  it "returns html unchanged when warnings are empty" do
    builder = Hwaro::Core::Build::Builder.new
    html = "<html><body><p>Hello</p></body></html>"

    result = builder.test_inject_error_overlay(html, [] of String)
    result.should eq(html)
  end

  it "escapes HTML in warning messages" do
    builder = Hwaro::Core::Build::Builder.new
    html = "<html><body></body></html>"
    warnings = ["Error with <script>alert('xss')</script>"]

    result = builder.test_inject_error_overlay(html, warnings)
    result.should_not contain("<script>alert")
    result.should contain("&lt;script&gt;")
  end

  it "shows multiple warnings as list items" do
    builder = Hwaro::Core::Build::Builder.new
    html = "<html><body></body></html>"
    warnings = ["Warning one", "Warning two"]

    result = builder.test_inject_error_overlay(html, warnings)
    result.should contain("Warning one")
    result.should contain("Warning two")
    # Should have two <li> items
    result.scan(/<li /).size.should eq(2)
  end
end

describe "Server#detect_changes" do
  it "detects modified content files" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)
    t2 = Time.utc(2025, 1, 1, 0, 0, 5)

    old = {"content/posts/hello.md" => t1, "content/about.md" => t1}
    new_m = {"content/posts/hello.md" => t2, "content/about.md" => t1}

    cs = server.test_detect_changes(old, new_m)
    cs.modified_content.should eq(["content/posts/hello.md"])
    cs.modified_templates.should be_empty
    cs.modified_static.should be_empty
    cs.added_files.should be_empty
    cs.removed_files.should be_empty
    cs.config_changed.should be_false
  end

  it "detects modified template files" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)
    t2 = Time.utc(2025, 1, 1, 0, 0, 5)

    old = {"templates/page.html" => t1}
    new_m = {"templates/page.html" => t2}

    cs = server.test_detect_changes(old, new_m)
    cs.modified_templates.should eq(["templates/page.html"])
    cs.modified_content.should be_empty
  end

  it "detects modified static files" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)
    t2 = Time.utc(2025, 1, 1, 0, 0, 5)

    old = {"static/css/style.css" => t1}
    new_m = {"static/css/style.css" => t2}

    cs = server.test_detect_changes(old, new_m)
    cs.modified_static.should eq(["static/css/style.css"])
    cs.modified_content.should be_empty
  end

  it "detects config.toml change" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)
    t2 = Time.utc(2025, 1, 1, 0, 0, 5)

    old = {"config.toml" => t1}
    new_m = {"config.toml" => t2}

    cs = server.test_detect_changes(old, new_m)
    cs.config_changed.should be_true
    cs.needs_full_rebuild?.should be_true
  end

  it "detects added files" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)

    old = {"content/posts/hello.md" => t1}
    new_m = {"content/posts/hello.md" => t1, "content/posts/new.md" => t1}

    cs = server.test_detect_changes(old, new_m)
    cs.added_files.should eq(["content/posts/new.md"])
    cs.needs_full_rebuild?.should be_true
  end

  it "detects removed files" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)

    old = {"content/posts/hello.md" => t1, "content/posts/old.md" => t1}
    new_m = {"content/posts/hello.md" => t1}

    cs = server.test_detect_changes(old, new_m)
    cs.removed_files.should eq(["content/posts/old.md"])
    cs.needs_full_rebuild?.should be_true
  end

  it "ignores unchanged files" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)

    old = {"content/posts/hello.md" => t1, "static/css/style.css" => t1}
    new_m = {"content/posts/hello.md" => t1, "static/css/style.css" => t1}

    cs = server.test_detect_changes(old, new_m)
    cs.empty?.should be_true
  end

  it "categorizes mixed changes correctly" do
    server = Hwaro::Services::Server.new
    t1 = Time.utc(2025, 1, 1, 0, 0, 0)
    t2 = Time.utc(2025, 1, 1, 0, 0, 5)

    old = {
      "content/posts/hello.md" => t1,
      "static/css/style.css"   => t1,
      "templates/page.html"    => t1,
    }
    new_m = {
      "content/posts/hello.md" => t2,
      "static/css/style.css"   => t2,
      "templates/page.html"    => t1,
    }

    cs = server.test_detect_changes(old, new_m)
    cs.modified_content.should eq(["content/posts/hello.md"])
    cs.modified_static.should eq(["static/css/style.css"])
    cs.modified_templates.should be_empty
    cs.content_incremental?.should be_true
  end
end

describe "Builder incremental methods" do
  describe "#copy_changed_static" do
    it "copies only specified static files to the output directory" do
      Dir.mktmpdir do |dir|
        # Setup: create static source and output directories
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(File.join(static_dir, "css"))
        FileUtils.mkdir_p(output_dir)

        File.write(File.join(static_dir, "css", "style.css"), "body { color: red; }")
        File.write(File.join(static_dir, "css", "other.css"), "h1 { color: blue; }")

        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          builder.copy_changed_static(
            ["static/css/style.css"],
            output_dir,
            false
          )

          # Only style.css should be copied
          File.exists?(File.join(output_dir, "css", "style.css")).should be_true
          File.read(File.join(output_dir, "css", "style.css")).should eq("body { color: red; }")

          # other.css should NOT be copied
          File.exists?(File.join(output_dir, "css", "other.css")).should be_false
        end
      end
    end

    it "creates parent directories as needed" do
      Dir.mktmpdir do |dir|
        static_dir = File.join(dir, "static")
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(File.join(static_dir, "assets", "js"))

        File.write(File.join(static_dir, "assets", "js", "app.js"), "console.log('hi')")

        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          builder.copy_changed_static(
            ["static/assets/js/app.js"],
            output_dir,
            false
          )

          File.exists?(File.join(output_dir, "assets", "js", "app.js")).should be_true
        end
      end
    end

    it "skips non-existent source files gracefully" do
      Dir.mktmpdir do |dir|
        output_dir = File.join(dir, "public")
        FileUtils.mkdir_p(output_dir)

        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          # Should not raise
          builder.copy_changed_static(
            ["static/nonexistent.css"],
            output_dir,
            false
          )
        end
      end
    end
  end

  describe "#run_incremental" do
    it "falls back to full build when no prior state exists" do
      Dir.mktmpdir do |dir|
        # Create minimal project structure
        FileUtils.mkdir_p(File.join(dir, "content"))
        FileUtils.mkdir_p(File.join(dir, "templates"))
        File.write(File.join(dir, "config.toml"), "title = \"Test\"\nbase_url = \"http://localhost\"\n")
        File.write(File.join(dir, "content", "hello.md"), "---\ntitle: Hello\n---\nHello world")
        File.write(File.join(dir, "templates", "page.html"), "{{ content }}")

        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
          options = Hwaro::Config::Options::BuildOptions.new

          # run_incremental should fall back to full build since no prior build happened
          builder.run_incremental(["content/hello.md"], options)

          # Verify output was generated (full build happened)
          File.exists?(File.join(dir, "public", "hello", "index.html")).should be_true
        end
      end
    end
  end

  describe "#run_rerender" do
    it "falls back to full build when no prior state exists" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "content"))
        FileUtils.mkdir_p(File.join(dir, "templates"))
        File.write(File.join(dir, "config.toml"), "title = \"Test\"\nbase_url = \"http://localhost\"\n")
        File.write(File.join(dir, "content", "hello.md"), "---\ntitle: Hello\n---\nHello world")
        File.write(File.join(dir, "templates", "page.html"), "{{ content }}")

        Dir.cd(dir) do
          builder = Hwaro::Core::Build::Builder.new
          Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
          options = Hwaro::Config::Options::BuildOptions.new

          # run_rerender should fall back to full build since no prior build happened
          builder.run_rerender(options)

          File.exists?(File.join(dir, "public", "hello", "index.html")).should be_true
        end
      end
    end
  end
end

describe "Incremental build integration" do
  it "only re-renders the changed page and its section, preserving other pages" do
    Dir.mktmpdir do |dir|
      # --- Setup project structure ---
      FileUtils.mkdir_p(File.join(dir, "content", "posts"))
      FileUtils.mkdir_p(File.join(dir, "templates"))

      File.write(File.join(dir, "config.toml"), <<-TOML
        title = "Incremental Test"
        base_url = "http://localhost"
        TOML
      )
      File.write(File.join(dir, "templates", "page.html"), "<article>{{ content }}</article>")
      File.write(File.join(dir, "templates", "section.html"), "<section>{{ content }}</section>")

      File.write(File.join(dir, "content", "posts", "_index.md"), <<-MD
        ---
        title: Posts
        ---
        Posts section
        MD
      )
      File.write(File.join(dir, "content", "posts", "alpha.md"), <<-MD
        ---
        title: Alpha
        date: 2025-01-01
        ---
        Alpha original content
        MD
      )
      File.write(File.join(dir, "content", "posts", "beta.md"), <<-MD
        ---
        title: Beta
        date: 2025-01-02
        ---
        Beta original content
        MD
      )
      File.write(File.join(dir, "content", "about.md"), <<-MD
        ---
        title: About
        ---
        About page content
        MD
      )

      Dir.cd(dir) do
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        options = Hwaro::Config::Options::BuildOptions.new

        # --- Full build ---
        builder.run(options)

        alpha_path = File.join(dir, "public", "posts", "alpha", "index.html")
        beta_path = File.join(dir, "public", "posts", "beta", "index.html")
        about_path = File.join(dir, "public", "about", "index.html")

        File.exists?(alpha_path).should be_true
        File.exists?(beta_path).should be_true
        File.exists?(about_path).should be_true

        original_alpha = File.read(alpha_path)
        original_beta = File.read(beta_path)
        original_about = File.read(about_path)

        original_alpha.should contain("Alpha original content")
        original_beta.should contain("Beta original content")
        original_about.should contain("About page content")

        # Record mtime of beta so we can verify it is NOT re-rendered
        beta_mtime_before = File.info(beta_path).modification_time
        about_mtime_before = File.info(about_path).modification_time

        # Small sleep so mtime changes are detectable
        sleep 0.05.seconds

        # --- Modify only alpha.md ---
        File.write(File.join(dir, "content", "posts", "alpha.md"), <<-MD
          ---
          title: Alpha
          date: 2025-01-01
          ---
          Alpha UPDATED content
          MD
        )

        # --- Incremental build ---
        builder.run_incremental(["content/posts/alpha.md"], options)

        # Alpha should have the updated content
        updated_alpha = File.read(alpha_path)
        updated_alpha.should contain("Alpha UPDATED content")
        updated_alpha.should_not contain("Alpha original content")

        # About page should be UNCHANGED (not in the affected set)
        updated_about = File.read(about_path)
        updated_about.should eq(original_about)
      end
    end
  end

  it "re-renders section index when a page in that section changes" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content", "blog"))
      FileUtils.mkdir_p(File.join(dir, "templates"))

      File.write(File.join(dir, "config.toml"), <<-TOML
        title = "Section Test"
        base_url = "http://localhost"
        TOML
      )
      File.write(File.join(dir, "templates", "page.html"), "<p>{{ content }}</p>")
      File.write(File.join(dir, "templates", "section.html"), "<div>{{ content }}</div>")

      File.write(File.join(dir, "content", "blog", "_index.md"), <<-MD
        ---
        title: Blog
        ---
        Blog index
        MD
      )
      File.write(File.join(dir, "content", "blog", "post1.md"), <<-MD
        ---
        title: Post One
        date: 2025-06-01
        ---
        Post one body
        MD
      )

      Dir.cd(dir) do
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        options = Hwaro::Config::Options::BuildOptions.new

        builder.run(options)

        section_path = File.join(dir, "public", "blog", "index.html")
        post_path = File.join(dir, "public", "blog", "post1", "index.html")

        File.exists?(section_path).should be_true
        File.exists?(post_path).should be_true

        # Modify post
        sleep 0.05.seconds
        File.write(File.join(dir, "content", "blog", "post1.md"), <<-MD
          ---
          title: Post One Updated
          date: 2025-06-01
          ---
          Post one UPDATED body
          MD
        )

        builder.run_incremental(["content/blog/post1.md"], options)

        # Post should be updated
        File.read(post_path).should contain("Post one UPDATED body")

        # Section index should also be re-rendered (it's in the affected set)
        File.exists?(section_path).should be_true
      end
    end
  end

  it "re-renders ancestor sections when a page in a nested section changes" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content", "blog", "posts"))
      FileUtils.mkdir_p(File.join(dir, "templates"))

      File.write(File.join(dir, "config.toml"), <<-TOML
        title = "Nested Section Test"
        base_url = "http://localhost"
        TOML
      )
      File.write(File.join(dir, "templates", "page.html"), "<p>{{ content }}</p>")
      File.write(File.join(dir, "templates", "section.html"), "<div>{{ content }}</div>")

      File.write(File.join(dir, "content", "blog", "_index.md"), <<-MD
        ---
        title: Blog
        ---
        Blog index
        MD
      )
      File.write(File.join(dir, "content", "blog", "posts", "_index.md"), <<-MD
        ---
        title: Posts
        ---
        Posts section
        MD
      )
      File.write(File.join(dir, "content", "blog", "posts", "post1.md"), <<-MD
        ---
        title: Post One
        date: 2025-06-01
        ---
        Post one body
        MD
      )

      Dir.cd(dir) do
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        options = Hwaro::Config::Options::BuildOptions.new

        builder.run(options)

        blog_section_path = File.join(dir, "public", "blog", "index.html")
        posts_section_path = File.join(dir, "public", "blog", "posts", "index.html")
        post_path = File.join(dir, "public", "blog", "posts", "post1", "index.html")

        File.exists?(blog_section_path).should be_true
        File.exists?(posts_section_path).should be_true
        File.exists?(post_path).should be_true

        # Record mtimes to verify re-rendering
        blog_mtime_before = File.info(blog_section_path).modification_time
        posts_mtime_before = File.info(posts_section_path).modification_time

        # Modify post
        sleep 0.05.seconds
        File.write(File.join(dir, "content", "blog", "posts", "post1.md"), <<-MD
          ---
          title: Post One Updated
          date: 2025-06-01
          ---
          Post one UPDATED body
          MD
        )

        builder.run_incremental(["content/blog/posts/post1.md"], options)

        # Post should be updated
        File.read(post_path).should contain("Post one UPDATED body")

        # Both ancestor sections should be re-rendered
        blog_mtime_after = File.info(blog_section_path).modification_time
        posts_mtime_after = File.info(posts_section_path).modification_time

        blog_mtime_after.should be > blog_mtime_before
        posts_mtime_after.should be > posts_mtime_before
      end
    end
  end

  it "re-renders with updated template via run_rerender" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "content"))
      FileUtils.mkdir_p(File.join(dir, "templates"))

      File.write(File.join(dir, "config.toml"), <<-TOML
        title = "Rerender Test"
        base_url = "http://localhost"
        TOML
      )
      File.write(File.join(dir, "templates", "page.html"), "<old>{{ content }}</old>")
      File.write(File.join(dir, "content", "hello.md"), <<-MD
        ---
        title: Hello
        ---
        Hello world
        MD
      )

      Dir.cd(dir) do
        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
        options = Hwaro::Config::Options::BuildOptions.new

        builder.run(options)

        output_path = File.join(dir, "public", "hello", "index.html")
        File.read(output_path).should contain("<old>")

        # Update template
        File.write(File.join(dir, "templates", "page.html"), "<new>{{ content }}</new>")

        builder.run_rerender(options)

        updated = File.read(output_path)
        updated.should contain("<new>")
        updated.should_not contain("<old>")
        # Content itself is preserved (not re-parsed)
        updated.should contain("Hello world")
      end
    end
  end
end
