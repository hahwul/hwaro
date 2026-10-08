require "../../spec_helper"
require "../../../src/services/importers/astro_importer"
require "../../../src/services/importers/eleventy_importer"
require "../../../src/services/importers/hexo_importer"
require "../../../src/services/importers/hugo_importer"
require "../../../src/services/importers/jekyll_importer"
require "../../../src/services/importers/notion_importer"
require "../../../src/services/importers/obsidian_importer"
require "../../../src/services/importers/wordpress_importer"

# Importer content-fidelity regressions: notes dropped or mangled on the way in.
module ImporterFidelitySpec
  def self.run(importer : Hwaro::Services::Importers::Base, type : String, src : String, dest : String)
    importer.run(Hwaro::Config::Options::ImportOptions.new(source_type: type, path: src, output_dir: dest))
  end

  def self.write(path : String, content : String)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def self.files(dir : String) : Array(String)
    Dir.glob(File.join(dir, "**", "*")).select { |f| File.file?(f) }.map(&.sub("#{dir}/", "")).sort!
  end
end

describe "importer fidelity" do
  describe "emoji- or symbol-only names" do
    it "imports Notion, Hexo, Astro, Eleventy, Jekyll and Obsidian notes instead of skipping them" do
      Dir.mktmpdir do |dir|
        ImporterFidelitySpec.write("#{dir}/notion/📚 0123456789abcdef0123456789abcdef.md", "# 📚\nNOTION_BODY\n")
        ImporterFidelitySpec.write("#{dir}/hexo/source/_posts/🎉.md", "---\ntitle: \"🎉\"\n---\nHEXO_BODY\n")
        ImporterFidelitySpec.write("#{dir}/astro/src/content/blog/🎉.md", "---\ntitle: \"🎉\"\n---\nASTRO_BODY\n")
        ImporterFidelitySpec.write("#{dir}/eleventy/🎉.md", "---\ntitle: \"🎉\"\n---\nELEVENTY_BODY\n")
        ImporterFidelitySpec.write("#{dir}/jekyll/_posts/🎉.md", "---\ntitle: \"🎉\"\n---\nJEKYLL_BODY\n")
        ImporterFidelitySpec.write("#{dir}/obsidian/note.md", "---\ntitle: \"!!!\"\n---\nOBSIDIAN_BODY\n")

        {
          "notion"   => {Hwaro::Services::Importers::NotionImporter.new, "NOTION_BODY"},
          "hexo"     => {Hwaro::Services::Importers::HexoImporter.new, "HEXO_BODY"},
          "astro"    => {Hwaro::Services::Importers::AstroImporter.new, "ASTRO_BODY"},
          "eleventy" => {Hwaro::Services::Importers::EleventyImporter.new, "ELEVENTY_BODY"},
          "jekyll"   => {Hwaro::Services::Importers::JekyllImporter.new, "JEKYLL_BODY"},
          "obsidian" => {Hwaro::Services::Importers::ObsidianImporter.new, "OBSIDIAN_BODY"},
        }.each do |type, (importer, marker)|
          dst = "#{dir}/out-#{type}"
          result = ImporterFidelitySpec.run(importer, type, "#{dir}/#{type}", dst)
          result.imported_count.should eq(1), "#{type}: #{result.message}"
          result.skipped_count.should eq(0), type
          ImporterFidelitySpec.files(dst).any? { |f| File.read("#{dst}/#{f}").includes?(marker) }.should be_true
        end
      end
    end

    it "tells the user why a note with no usable slug was skipped" do
      Dir.mktmpdir do |dir|
        ImporterFidelitySpec.write("#{dir}/hugo/content/posts/x.md", "+++\ntitle=\"X\"\nslug=\"/\"\n+++\nbody\n")
        result = nil
        log = with_captured_log do
          result = ImporterFidelitySpec.run(Hwaro::Services::Importers::HugoImporter.new, "hugo", "#{dir}/hugo", "#{dir}/out")
        end
        result.try(&.skipped_count).should eq(1)
        log.should contain("unusable slug")
      end
    end
  end

  describe "Hugo translations with a front matter slug" do
    it "keeps the language suffix and the bundle shape" do
      Dir.mktmpdir do |dir|
        c = "#{dir}/hugo/content/posts"
        ImporterFidelitySpec.write("#{c}/a.md", "+++\ntitle=\"A\"\nslug=\"shared\"\n+++\nEN\n")
        ImporterFidelitySpec.write("#{c}/a.ko.md", "+++\ntitle=\"가\"\nslug=\"shared\"\n+++\nKO\n")
        ImporterFidelitySpec.write("#{c}/trip/index.md", "+++\ntitle=\"Trip\"\nslug=\"journey\"\n+++\n![x](pic.png)\n")
        ImporterFidelitySpec.write("#{c}/trip/index.ko.md", "+++\ntitle=\"여행\"\nslug=\"other\"\n+++\n![x](pic.png)\n")
        ImporterFidelitySpec.write("#{c}/trip/pic.png", "p")

        dst = "#{dir}/out"
        ImporterFidelitySpec.run(Hwaro::Services::Importers::HugoImporter.new, "hugo", "#{dir}/hugo", dst)

        ImporterFidelitySpec.files(dst).should eq([
          "posts/journey/index.ko.md",
          "posts/journey/index.md",
          "posts/journey/pic.png",
          "posts/shared.ko.md",
          "posts/shared.md",
        ])
        File.read("#{dst}/posts/shared.md").should contain("EN")
        File.read("#{dst}/posts/shared.ko.md").should contain("KO")
      end
    end

    it "does not read a dotted name that is not a language as a translation" do
      Dir.mktmpdir do |dir|
        ImporterFidelitySpec.write("#{dir}/hugo/content/posts/release.notes.md", "+++\ntitle=\"R\"\nslug=\"rel\"\n+++\nR\n")
        dst = "#{dir}/out"
        ImporterFidelitySpec.run(Hwaro::Services::Importers::HugoImporter.new, "hugo", "#{dir}/hugo", dst)
        ImporterFidelitySpec.files(dst).should eq(["posts/rel.md"])
      end
    end
  end

  describe "bundle assets" do
    it "copies Hugo assets beside translated-only leaf bundles and branch bundles" do
      Dir.mktmpdir do |dir|
        c = "#{dir}/hugo/content"
        ImporterFidelitySpec.write("#{c}/posts/trip/index.ko.md", "+++\ntitle=\"T\"\n+++\n![x](cover.png)\n")
        ImporterFidelitySpec.write("#{c}/posts/trip/cover.png", "c")
        ImporterFidelitySpec.write("#{c}/docs/_index.md", "+++\ntitle=\"D\"\n+++\nbody\n")
        ImporterFidelitySpec.write("#{c}/docs/diagram.png", "d")
        dst = "#{dir}/out"
        ImporterFidelitySpec.run(Hwaro::Services::Importers::HugoImporter.new, "hugo", "#{dir}/hugo", dst)
        File.exists?("#{dst}/posts/trip/cover.png").should be_true
        File.exists?("#{dst}/docs/diagram.png").should be_true
      end
    end

    it "writes an Astro bundle with assets as a bundle" do
      Dir.mktmpdir do |dir|
        ImporterFidelitySpec.write("#{dir}/astro/src/content/blog/bundle/index.md", "---\ntitle: B\n---\n![c](./cover.png)\n")
        ImporterFidelitySpec.write("#{dir}/astro/src/content/blog/bundle/cover.png", "c")
        ImporterFidelitySpec.write("#{dir}/astro/src/content/blog/plain/index.md", "---\ntitle: P\n---\nbody\n")
        dst = "#{dir}/out"
        ImporterFidelitySpec.run(Hwaro::Services::Importers::AstroImporter.new, "astro", "#{dir}/astro", dst)
        ImporterFidelitySpec.files(dst).should eq(["blog/bundle/cover.png", "blog/bundle/index.md", "blog/plain.md"])
      end
    end
  end

  describe "Obsidian" do
    it "resolves aliased wikilinks escaped for tables" do
      Dir.mktmpdir do |dir|
        ImporterFidelitySpec.write("#{dir}/v/Target.md", "# Target\nbody\n")
        ImporterFidelitySpec.write("#{dir}/v/Table.md", "| a | b |\n|---|---|\n| [[Target\\|shown]] | [[Target#Sec\\|x]] |\n\nplain [[Target|plain alias]]\n")
        dst = "#{dir}/out"
        ImporterFidelitySpec.run(Hwaro::Services::Importers::ObsidianImporter.new, "obsidian", "#{dir}/v", dst)
        content = File.read("#{dst}/posts/table.md")
        content.should contain("| [shown](/posts/target/) | [x](/posts/target/#sec) |")
        content.should contain("[plain alias](/posts/target/)")
      end
    end

    it "points links at the collision-renamed file of a same-titled note" do
      Dir.mktmpdir do |dir|
        ImporterFidelitySpec.write("#{dir}/v/w1.md", "---\ntitle: Weekly\n---\nw1body\n")
        ImporterFidelitySpec.write("#{dir}/v/w2.md", "---\ntitle: Weekly\n---\nw2body\n")
        ImporterFidelitySpec.write("#{dir}/v/index-note.md", "See [[w1]] and [[w2]]\n")
        dst = "#{dir}/out"
        ImporterFidelitySpec.run(Hwaro::Services::Importers::ObsidianImporter.new, "obsidian", "#{dir}/v", dst)
        File.read("#{dst}/posts/weekly.md").should contain("w1body")
        File.read("#{dst}/posts/weekly-1.md").should contain("w2body")
        File.read("#{dst}/posts/index-note.md").should contain("See [w1](/posts/weekly/) and [w2](/posts/weekly-1/)")
      end
    end

    it "treats a blank or null title as absent" do
      Dir.mktmpdir do |dir|
        ImporterFidelitySpec.write("#{dir}/v/My Note.md", "---\ntitle:\ntags: [a]\n---\nBody of note\n")
        ImporterFidelitySpec.write("#{dir}/v/Second.md", "---\ntitle: \"\"\n---\nBody\n")
        dst = "#{dir}/out"
        result = ImporterFidelitySpec.run(Hwaro::Services::Importers::ObsidianImporter.new, "obsidian", "#{dir}/v", dst)
        result.imported_count.should eq(2)
        File.read("#{dst}/posts/my-note.md").should contain(%(title = "My Note"))
        File.read("#{dst}/posts/second.md").should contain(%(title = "Second"))
      end
    end

    it "keeps unquoted dates readable and machine-independent" do
      Dir.mktmpdir do |dir|
        ImporterFidelitySpec.write("#{dir}/v/daily.md", "---\ntitle: 2024-05-01\ntags: [2024-05-01]\n---\nBody\n")
        dst = "#{dir}/out"
        ImporterFidelitySpec.run(Hwaro::Services::Importers::ObsidianImporter.new, "obsidian", "#{dir}/v", dst)
        ImporterFidelitySpec.files(dst).should eq(["posts/2024-05-01.md"])
        content = File.read("#{dst}/posts/2024-05-01.md")
        content.should contain(%(title = "2024-05-01"))
        content.should contain(%(tags = ["2024-05-01"]))
      end
    end

    it "leaves #fff in HTML attributes and #b in math alone" do
      Dir.mktmpdir do |dir|
        ImporterFidelitySpec.write("#{dir}/v/n.md", "Color: <span style=\"color: #fff\">white</span> and #todo item.\nMath: $a #b$ and `#code`.\n<a href=\"[[x]]\">l</a>\n$$\n#c\n$$\n")
        dst = "#{dir}/out"
        ImporterFidelitySpec.run(Hwaro::Services::Importers::ObsidianImporter.new, "obsidian", "#{dir}/v", dst)
        content = File.read("#{dst}/posts/n.md")
        content.should contain(%(<span style="color: #fff">white</span> and  item.))
        content.should contain("Math: $a #b$ and `#code`.")
        content.should contain(%(<a href="[[x]]">l</a>))
        content.should contain("$$\n#c\n$$")
        content.should contain(%(tags = ["todo"]))
      end
    end
  end

  describe "Notion" do
    it "links each page to the file its target was actually written to" do
      Dir.mktmpdir do |dir|
        n = "#{dir}/nt"
        parent = "Parent 0123456789abcdef0123456789abcdef"
        other = "Other 11111111111111111111111111111111"
        ImporterFidelitySpec.write("#{n}/#{parent}.md", "# Parent\n[Child](Parent%200123456789abcdef0123456789abcdef/Child%20Page%2022222222222222222222222222222222.md)\n")
        ImporterFidelitySpec.write("#{n}/#{other}.md", "# Other\n[Child](Other%2011111111111111111111111111111111/Child%20Page%2033333333333333333333333333333333.md)\n")
        ImporterFidelitySpec.write("#{n}/#{parent}/Child Page 22222222222222222222222222222222.md", "# Child Page\nchild1\n")
        ImporterFidelitySpec.write("#{n}/#{other}/Child Page 33333333333333333333333333333333.md", "# Child Page\nchild2\n")
        dst = "#{dir}/out"
        ImporterFidelitySpec.run(Hwaro::Services::Importers::NotionImporter.new, "notion", n, dst)
        # Walk order: Other/ sorts before Parent/, so Other's child owns the plain slug.
        File.read("#{dst}/posts/child-page.md").should contain("child2")
        File.read("#{dst}/posts/child-page-1.md").should contain("child1")
        File.read("#{dst}/posts/parent.md").should contain("(/posts/child-page-1/)")
        File.read("#{dst}/posts/other.md").should contain("(/posts/child-page/)")
      end
    end

    it "flattens only real callouts and leaves quotes, fences and code spans alone" do
      Dir.mktmpdir do |dir|
        body = "# Page\n\n> 💡 Real callout\n> - item one\n> > nested quote\n> # Heading in quote\n> — Author name\n\n```md\n> - item one\n> # heading\n```\n\nSee `[bookmark](http://a)` and [bookmark](http://b)\n"
        ImporterFidelitySpec.write("#{dir}/nt/page.md", body)
        dst = "#{dir}/out"
        ImporterFidelitySpec.run(Hwaro::Services::Importers::NotionImporter.new, "notion", "#{dir}/nt", dst)
        content = File.read("#{dst}/posts/page.md")
        content.should contain("> Real callout")
        content.should contain("> - item one\n> > nested quote\n> # Heading in quote\n> — Author name")
        content.should contain("```md\n> - item one\n> # heading\n```")
        content.should contain("`[bookmark](http://a)`")
        content.should contain("[http://b](http://b)")
      end
    end

    it "falls back to the heading when the title is blank" do
      Dir.mktmpdir do |dir|
        ImporterFidelitySpec.write("#{dir}/nt/page.md", "---\ntitle:\n---\n# Heading One\n\nbody\n")
        dst = "#{dir}/out"
        ImporterFidelitySpec.run(Hwaro::Services::Importers::NotionImporter.new, "notion", "#{dir}/nt", dst)
        content = File.read("#{dst}/posts/page.md")
        content.should contain(%(title = "Heading One"))
        content.should_not contain("# Heading One")
      end
    end
  end

  describe "title fallbacks" do
    it "derives Jekyll and Hexo titles from the file name" do
      Dir.mktmpdir do |dir|
        ImporterFidelitySpec.write("#{dir}/nt/_posts/2024-01-01-my-great-post.md", "No title body\n")
        ImporterFidelitySpec.write("#{dir}/nt/source/_posts/hexo-great-post.md", "---\ntags: [x]\n---\nHexo no title\n")
        ImporterFidelitySpec.run(Hwaro::Services::Importers::JekyllImporter.new, "jekyll", "#{dir}/nt", "#{dir}/j")
        ImporterFidelitySpec.run(Hwaro::Services::Importers::HexoImporter.new, "hexo", "#{dir}/nt", "#{dir}/h")
        File.read("#{dir}/j/posts/my-great-post.md").should contain(%(title = "My Great Post"))
        File.read("#{dir}/h/posts/hexo-great-post.md").should contain(%(title = "hexo-great-post"))
      end
    end

    it "derives Astro and Eleventy titles when `title:` is blank" do
      Dir.mktmpdir do |dir|
        ImporterFidelitySpec.write("#{dir}/astro/src/content/blog/my-post.md", "---\ntitle:\npubDate: 2024-01-01\n---\nbody\n")
        ImporterFidelitySpec.write("#{dir}/el/my-el-post.md", "---\ntitle:\n---\nbody\n")
        ImporterFidelitySpec.run(Hwaro::Services::Importers::AstroImporter.new, "astro", "#{dir}/astro", "#{dir}/oa")
        ImporterFidelitySpec.run(Hwaro::Services::Importers::EleventyImporter.new, "eleventy", "#{dir}/el", "#{dir}/oe")
        File.read("#{dir}/oa/blog/my-post.md").should contain(%(title = "My Post"))
        File.read("#{dir}/oe/posts/my-el-post.md").should contain(%(title = "My El Post"))
      end
    end
  end

  describe "Jekyll and Hexo date-prefixed slugs" do
    it "slugifies the name so URLs are safe" do
      Dir.mktmpdir do |dir|
        ImporterFidelitySpec.write("#{dir}/s/_posts/2024-01-01-Hello World.md", "---\ntitle: a\n---\nx\n")
        ImporterFidelitySpec.write("#{dir}/s/_posts/2024-01-04-100%.markdown", "---\ntitle: b\n---\nx\n")
        ImporterFidelitySpec.write("#{dir}/s/_posts/2024-01-03-a#b?c.md", "---\ntitle: c\n---\nx\n")
        ImporterFidelitySpec.write("#{dir}/s/source/_posts/2024-01-04-100% Real.md", "---\ntitle: d\n---\nx\n")
        ImporterFidelitySpec.run(Hwaro::Services::Importers::JekyllImporter.new, "jekyll", "#{dir}/s", "#{dir}/j")
        ImporterFidelitySpec.run(Hwaro::Services::Importers::HexoImporter.new, "hexo", "#{dir}/s", "#{dir}/h")
        ImporterFidelitySpec.files("#{dir}/j").should eq(["posts/100.md", "posts/abc.md", "posts/hello-world.md"].sort)
        ImporterFidelitySpec.files("#{dir}/h").should eq(["posts/100-real.md"])
      end
    end
  end

  describe "Hugo date titles" do
    it "keeps an unquoted YAML date title as written" do
      Dir.mktmpdir do |dir|
        ImporterFidelitySpec.write("#{dir}/hugo/content/posts/d.md", "---\ntitle: 2024-05-01\n---\nbody\n")
        dst = "#{dir}/out"
        ImporterFidelitySpec.run(Hwaro::Services::Importers::HugoImporter.new, "hugo", "#{dir}/hugo", dst)
        File.read("#{dst}/posts/d.md").should contain(%(title = "2024-05-01"))
      end
    end
  end

  describe "WordPress HTML" do
    it "drops script and style bodies and keeps embeds" do
      html = %(<style>.a{color:red}</style><script>var tracker = "x < y";</script><iframe src="https://www.youtube.com/embed/abc" width="560" onload="evil()"></iframe><video src="a.mp4"></video><iframe src="javascript:alert(1)"></iframe><p>Price: $5 &amp; up</p>)
      md = Hwaro::Services::Importers::HtmlToMarkdown.convert(html)
      md.should_not contain("color:red")
      md.should_not contain("tracker")
      md.should contain(%(<iframe src="https://www.youtube.com/embed/abc" width="560" allowfullscreen></iframe>))
      md.should contain(%(<video src="a.mp4" controls></video>))
      md.should_not contain("javascript:")
      md.should_not contain("onload")
      md.should contain("Price: $5 & up")
    end
  end
end
