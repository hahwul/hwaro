require "../spec_helper"
require "../../src/core/build/builder"

# SnapshotTemplateLoader serves {% include %}/{% extends %} references from
# the in-memory template snapshot so a serve rebuild can't observe files an
# editor is rewriting mid-render. References the snapshot can't answer fall
# back to the filesystem loader, matching the old behavior exactly.

private def with_templates_dir(&)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      FileUtils.mkdir_p("templates/partials")
      yield dir
    end
  end
end

private def build_loader(
  templates : Hash(String, String),
  paths : Hash(String, String),
) : Hwaro::Core::Build::SnapshotTemplateLoader
  Hwaro::Core::Build::SnapshotTemplateLoader.new(
    templates, paths, Crinja::Loader::FileSystemLoader.new("templates/")
  )
end

describe Hwaro::Core::Build::SnapshotTemplateLoader do
  it "serves a referenced partial from the snapshot, not from disk" do
    with_templates_dir do
      File.write("templates/partials/nav.html", "DISK")
      loader = build_loader(
        {"partials/nav" => "SNAPSHOT"},
        {"partials/nav" => "templates/partials/nav.html"},
      )

      source, file_name = loader.get_source(Crinja.new, "partials/nav.html")
      source.should eq("SNAPSHOT")
      file_name.should eq("templates/partials/nav.html")
    end
  end

  it "keeps serving the snapshot when the file on disk was rewritten mid-build" do
    with_templates_dir do
      File.write("templates/partials/nav.html", "OLD")
      loader = build_loader(
        {"partials/nav" => "OLD"},
        {"partials/nav" => "templates/partials/nav.html"},
      )

      # Editor rewrites the partial while a render is in flight — even a
      # half-written file must not leak into this build's output.
      File.write("templates/partials/nav.html", "HALF-WRIT")

      source, _ = loader.get_source(Crinja.new, "partials/nav.html")
      source.should eq("OLD")
    end
  end

  it "falls back to disk for names outside the snapshot" do
    with_templates_dir do
      File.write("templates/partials/foot.html", "DISK-ONLY")
      loader = build_loader(
        {"partials/nav" => "SNAPSHOT"},
        {"partials/nav" => "templates/partials/nav.html"},
      )

      source, _ = loader.get_source(Crinja.new, "partials/foot.html")
      source.should eq("DISK-ONLY")
    end
  end

  it "falls back to disk for an extension variant the snapshot didn't load" do
    with_templates_dir do
      # foo.html won the snapshot slot (extension priority), but the
      # reference names foo.j2 explicitly — read its own file, like the
      # filesystem loader would.
      File.write("templates/foo.j2", "J2-DISK")
      loader = build_loader(
        {"foo" => "HTML-SNAPSHOT"},
        {"foo" => "templates/foo.html"},
      )

      source, _ = loader.get_source(Crinja.new, "foo.j2")
      source.should eq("J2-DISK")
    end
  end

  it "does not claim extension-less references (filesystem semantics preserved)" do
    with_templates_dir do
      loader = build_loader(
        {"partials/nav" => "SNAPSHOT"},
        {"partials/nav" => "templates/partials/nav.html"},
      )

      # `{% include "partials/nav" %}` never resolved via the stripped-name
      # hash before; the literal file doesn't exist, so this stays an error.
      expect_raises(Crinja::TemplateNotFoundError) do
        loader.get_source(Crinja.new, "partials/nav")
      end
    end
  end
end
