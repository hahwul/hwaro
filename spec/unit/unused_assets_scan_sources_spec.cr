require "../spec_helper"

# Finding 2: `collect_scan_text` only globbed `templates/**/*.{html,css,js}`
# and `static/**/*.{css,js}`. Assets referenced from any other file the build
# consumes — `.jinja`/`.j2`/`.ecr` templates, Sass sources, feed templates,
# PWA manifests, SVGs — were reported unused, and `--delete --force`
# (documented for CI) then removed files the site still needs.
private def unused_basenames(dir : String) : Array(String)
  service = Hwaro::Services::UnusedAssets.new(
    content_dir: File.join(dir, "content"),
    static_dir: File.join(dir, "static"),
    templates_dir: File.join(dir, "templates"),
  )
  service.run.unused_files.map { |f| File.basename(f) }.sort!
end

private def scaffold_project(dir : String)
  %w[content static templates].each { |d| FileUtils.mkdir_p(File.join(dir, d)) }
  File.write(File.join(dir, "content", "_index.md"), "---\ntitle: H\n---\nBody")
end

describe Hwaro::Services::UnusedAssets do
  describe "reference sources" do
    it "sees assets referenced from a .jinja template" do
      Dir.mktmpdir do |dir|
        scaffold_project(dir)
        File.write(File.join(dir, "templates", "base.html.jinja"), %(<img src="/img/hero.png">))
        File.write(File.join(dir, "static", "hero.png"), "png")

        unused_basenames(dir).should be_empty
      end
    end

    it "sees assets referenced from a .j2 / .ecr template" do
      Dir.mktmpdir do |dir|
        scaffold_project(dir)
        File.write(File.join(dir, "templates", "nav.j2"), %(<img src="/a.png">))
        File.write(File.join(dir, "templates", "card.ecr"), %(<img src="/b.png">))
        File.write(File.join(dir, "static", "a.png"), "png")
        File.write(File.join(dir, "static", "b.png"), "png")

        unused_basenames(dir).should be_empty
      end
    end

    it "sees fonts referenced from a Sass source under static/" do
      Dir.mktmpdir do |dir|
        scaffold_project(dir)
        FileUtils.mkdir_p(File.join(dir, "static", "css"))
        File.write(File.join(dir, "static", "css", "main.scss"), "@font-face{src:url(/fonts/inter.woff2)}")
        FileUtils.mkdir_p(File.join(dir, "static", "fonts"))
        File.write(File.join(dir, "static", "fonts", "inter.woff2"), "font")

        unused_basenames(dir).should be_empty
      end
    end

    it "sees icons referenced from a PWA web app manifest" do
      Dir.mktmpdir do |dir|
        scaffold_project(dir)
        File.write(File.join(dir, "static", "site.webmanifest"),
          %({"icons":[{"src":"/icons/app-192.png"}]}))
        FileUtils.mkdir_p(File.join(dir, "static", "icons"))
        File.write(File.join(dir, "static", "icons", "app-192.png"), "png")

        unused_basenames(dir).should be_empty
      end
    end

    it "sees images referenced from an XML feed template" do
      Dir.mktmpdir do |dir|
        scaffold_project(dir)
        File.write(File.join(dir, "templates", "rss.xml.jinja"), "<image>/feed-logo.png</image>")
        File.write(File.join(dir, "static", "feed-logo.png"), "png")

        unused_basenames(dir).should be_empty
      end
    end

    it "sees images referenced from inside an SVG" do
      Dir.mktmpdir do |dir|
        scaffold_project(dir)
        File.write(File.join(dir, "templates", "index.html"), %(<img src="/outer.svg">))
        File.write(File.join(dir, "static", "outer.svg"), %(<svg><image href="/inner.png"/></svg>))
        File.write(File.join(dir, "static", "inner.png"), "png")

        unused_basenames(dir).should be_empty
      end
    end

    it "still reports a genuinely unreferenced asset" do
      Dir.mktmpdir do |dir|
        scaffold_project(dir)
        File.write(File.join(dir, "templates", "base.html.jinja"), %(<img src="/used.png">))
        File.write(File.join(dir, "static", "used.png"), "png")
        File.write(File.join(dir, "static", "orphan.png"), "png")

        unused_basenames(dir).should eq(["orphan.png"])
      end
    end
  end
end
