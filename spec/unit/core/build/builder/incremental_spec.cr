require "../../../../spec_helper"
require "../../../../../src/core/build/builder"
require "../../../../../src/content/hooks"

class Hwaro::Core::Build::Builder
  def test_priority_pages : Array(Hwaro::Models::Page)
    @priority_pages
  end
end

describe "Builder#run_incremental output collisions" do
  it "republishes a bundle's assets once the collision that suppressed it is gone" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
        FileUtils.mkdir_p("content/posts/a")
        FileUtils.mkdir_p("content/posts/x")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ page.title }}")
        File.write("content/posts/a/index.md", "+++\ntitle = \"A\"\n+++\n")
        File.write("content/posts/a/cover.png", "A-cover")
        File.write("content/posts/x/index.md", "+++\ntitle = \"X\"\n+++\n")
        File.write("content/posts/x/cover.png", "X-cover")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/posts/a/index.md"], options)

        # posts/a takes /posts/x/ (it sorts first): the URL serves A's files.
        File.write("content/posts/a/index.md", "+++\ntitle = \"A\"\nslug = \"x\"\n+++\n")
        builder.run_incremental(["content/posts/a/index.md"], options)
        File.read("public/posts/x/index.html").should eq("A")
        File.read("public/posts/x/cover.png").should eq("A-cover")

        # Collision resolved: posts/x owns /posts/x/ again, files included.
        File.write("content/posts/a/index.md", "+++\ntitle = \"A\"\n+++\n")
        builder.run_incremental(["content/posts/a/index.md"], options)
        File.read("public/posts/x/index.html").should eq("X")
        File.read("public/posts/x/cover.png").should eq("X-cover")
        File.read("public/posts/a/cover.png").should eq("A-cover")
      end
    end
  end

  it "re-renders a page once the collision that suppressed it is gone" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
        FileUtils.mkdir_p("content/posts")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ page.title }}")
        # `m` sits between `a` and `b` in date order, so `b` neither links
        # to `a` nor neighbours it: nothing but the collision ties them.
        File.write("content/posts/a.md", "+++\ntitle = \"A\"\ndate = 2024-01-01\n+++\n")
        File.write("content/posts/m.md", "+++\ntitle = \"M\"\ndate = 2024-01-02\n+++\n")
        File.write("content/posts/m2.md", "+++\ntitle = \"M2\"\ndate = 2024-01-03\n+++\n")
        File.write("content/posts/b.md", "+++\ntitle = \"B\"\ndate = 2024-01-04\n+++\n")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/posts/a.md"], options)

        File.write("content/posts/a.md", "+++\ntitle = \"A\"\ndate = 2024-01-01\nslug = \"b\"\n+++\n")
        builder.run_incremental(["content/posts/a.md"], options)
        File.read("public/posts/b/index.html").should eq("A")

        File.write("content/posts/a.md", "+++\ntitle = \"A\"\ndate = 2024-01-01\n+++\n")
        builder.run_incremental(["content/posts/a.md"], options)
        File.read("public/posts/a/index.html").should eq("A")
        File.read("public/posts/b/index.html").should eq("B")
      end
    end
  end
end

# `site.authors` embeds each page's title and summary; only the full build's
# Transform phase built it, so serve kept printing the pre-edit values.
describe "Builder serve passes and site.authors" do
  it "refreshes author page lists after a content edit and a shortcode edit" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
        FileUtils.mkdir_p("content/blog")
        FileUtils.mkdir_p("templates/shortcodes")
        File.write("templates/page.html", "{{ content }}")
        File.write("templates/section.html", "A[{% for p in site.authors.ann.pages %}{{ p.title }}:{{ p.summary }}{% endfor %}]")
        File.write("templates/shortcodes/sc.html", "one")
        File.write("content/blog/_index.md", "+++\ntitle = \"B\"\n+++\n")
        post = "+++\ntitle = \"Old\"\nauthors = [\"ann\"]\n+++\nIntro {{ sc() }}\n\n<!-- more -->\n\nRest.\n"
        File.write("content/blog/post.md", post)

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/blog/post.md"], options)
        File.read("public/blog/index.html").should eq("A[Old:<p>Intro one</p>\n]")

        File.write("content/blog/post.md", post.sub("Old", "New").sub("Intro", "Lead"))
        builder.run_incremental(["content/blog/post.md"], options)
        File.read("public/blog/index.html").should eq("A[New:<p>Lead one</p>\n]")

        File.write("templates/shortcodes/sc.html", "two")
        builder.run_rerender(options)
        File.read("public/blog/index.html").should eq("A[New:<p>Lead two</p>\n]")
      end
    end
  end
end

describe "Builder#run_incremental listing fan-out" do
  it "refreshes sibling section.pages loops when a subsection's body changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
        FileUtils.mkdir_p("content/blog/sub")
        FileUtils.mkdir_p("templates")
        listing = "{% for p in section.pages %}[{{ p.title }}:{{ p.summary }}]{% endfor %}"
        File.write("templates/page.html", listing)
        File.write("templates/section.html", listing)
        File.write("content/blog/_index.md", "+++\ntitle = \"Blog\"\n+++\n")
        File.write("content/blog/sub/_index.md", "+++\ntitle = \"Sub\"\n+++\nold\n")
        File.write("content/blog/a.md", "+++\ntitle = \"A\"\n+++\na\n")
        File.write("content/blog/b.md", "+++\ntitle = \"B\"\n+++\nb\n")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/blog/sub/_index.md"], options)
        File.read("public/blog/a/index.html").should contain("<p>old</p>")

        # Only the subsection's body moves: its title, URL and the section
        # set are unchanged, so only the page-set projection can see it.
        File.write("content/blog/sub/_index.md", "+++\ntitle = \"Sub\"\n+++\nnew\n")
        builder.run_incremental(["content/blog/sub/_index.md"], options)
        File.read("public/blog/a/index.html").should contain("<p>new</p>")
        File.read("public/blog/b/index.html").should contain("<p>new</p>")
      end
    end
  end
end

describe "Builder#run_incremental term body shortcodes" do
  # A term `_index.md` is headless: only its body (`term_content`) renders,
  # and a shortcode in it reads other pages like one in any page body does.
  it "refreshes a term body that reads an edited page through a shortcode" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n[[taxonomies]]\nname = "tags"\n))
        FileUtils.mkdir_p("content/tags/t")
        FileUtils.mkdir_p("templates/shortcodes")
        File.write("templates/page.html", "{{ content }}")
        File.write("templates/section.html", "{{ content }}")
        File.write("templates/taxonomy.html", "{{ content }}")
        File.write("templates/taxonomy_term.html", %(<div class="tc">{{ term_content }}</div>))
        File.write("templates/shortcodes/ptitle.html", "<b>{{ get_page(path=path).title }}</b>")
        File.write("templates/shortcodes/plist.html", %({% for p in get_section(path="_index.md").pages %}<i>{{ p.title }}</i>{% endfor %}))
        File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
        File.write("content/a.md", "+++\ntitle = \"A\"\ntags = [\"t\"]\n+++\na\n")
        File.write("content/b.md", "+++\ntitle = \"B1\"\n+++\nb\n")
        File.write("content/tags/t/_index.md", %(+++\ntitle = "T"\n+++\nSee {{ ptitle(path="b.md") }} {{ plist() }}\n))

        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/b.md"], options)
        term = "public/tags/t/index.html"
        File.read(term).should contain("<b>B1</b> <i>A</i><i>B1</i>")

        File.write("content/b.md", "+++\ntitle = \"B2\"\n+++\nb\n")
        builder.run_incremental(["content/b.md"], options).should be_true
        File.read(term).should contain("<b>B2</b> <i>A</i><i>B2</i>")

        # The same through a combined content + template pass.
        File.write("templates/page.html", "<main>{{ content }}</main>")
        File.write("content/b.md", "+++\ntitle = \"B3\"\n+++\nb\n")
        builder.run_incremental_then_rerender(["content/b.md"], options).should be_true
        File.read(term).should contain("<b>B3</b> <i>A</i><i>B3</i>")
      end
    end
  end

  # A term body's entry template (`section.html`) never renders it, so its
  # listing markers must not select a body without shortcodes.
  it "leaves term bodies without shortcodes alone" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n[[taxonomies]]\nname = "tags"\n))
        FileUtils.mkdir_p("templates/shortcodes")
        File.write("templates/page.html", "{{ content }}")
        FileUtils.mkdir_p("content")
        File.write("templates/section.html", "{% for p in section.pages %}{{ p.title }}{% endfor %}{{ content }}")
        File.write("templates/taxonomy.html", "{{ content }}")
        File.write("templates/taxonomy_term.html", "{{ term_content }}")
        File.write("templates/shortcodes/ptitle.html", "<b>{{ get_page(path=path).title }}</b>")
        File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
        File.write("content/b.md", "+++\ntitle = \"B1\"\n+++\nb\n")
        %w[t u v w].each do |t|
          FileUtils.mkdir_p("content/tags/#{t}")
          File.write("content/#{t}.md", "+++\ntitle = \"#{t}\"\ntags = [\"#{t}\"]\n+++\nx\n")
          File.write("content/tags/#{t}/_index.md", "+++\ntitle = \"#{t}\"\n+++\nplain\n")
        end
        File.write("content/tags/t/_index.md", %(+++\ntitle = "t"\n+++\nSee {{ ptitle(path="b.md") }}\n))

        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/b.md"], options)

        File.write("content/b.md", "+++\ntitle = \"B2\"\n+++\nb\n")
        log = with_captured_log { builder.run_incremental(["content/b.md"], options).should be_true }
        File.read("public/tags/t/index.html").should contain("<b>B2</b>")
        # b, its reading-order neighbour, the home listing and the one body
        # with a shortcode — not the u/v/w bodies.
        log.should contain("rebuilt: 4/")
      end
    end
  end
end

describe "Builder#run_incremental summary shortcodes" do
  # A and C never change, but their summaries print B's title through a
  # shortcode, and the listing prints those summaries.
  it "refreshes the summaries of pages whose shortcodes read an edited page" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates/shortcodes")
        File.write("templates/page.html", "{{ content }}")
        File.write("templates/section.html", "{% for p in section.pages %}[{{ p.title }}::{{ p.summary | safe }}]{% endfor %}")
        File.write("templates/shortcodes/btitle.html", %(<b>{{ get_page(path="b.md").title }}</b>))
        File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
        File.write("content/a.md", "+++\ntitle = \"A\"\n+++\nA mentions {{ btitle() }} here.\n")
        File.write("content/c.md", "+++\ntitle = \"C\"\n+++\nC {{ btitle() }} first\n<!-- more -->\nrest\n")
        File.write("content/b.md", "+++\ntitle = \"B1\"\n+++\nb\n")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/b.md"], options)
        File.read("public/index.html").should contain("[A::<p>A mentions B1 here.</p>")

        File.write("content/b.md", "+++\ntitle = \"B2\"\n+++\nb\n")
        builder.run_incremental(["content/b.md"], options).should be_true
        html = File.read("public/index.html")
        html.should contain("[A::<p>A mentions B2 here.</p>")
        html.should contain("[C::<p>C <b>B2</b> first</p>")
      end
    end
  end

  # C's summary prints A's, which prints B's title: both are recomputed in
  # one pass, and C must read A's NEW summary, as a cold build does.
  it "refreshes a summary that prints another recomputed summary" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates/shortcodes")
        File.write("templates/page.html", "{{ content }}")
        File.write("templates/section.html", "{% for p in section.pages %}[{{ p.title }}::{{ p.summary | safe }}]{% endfor %}")
        File.write("templates/shortcodes/t.html", "{% set q = get_page(path=path) %}({{ q.title }})")
        File.write("templates/shortcodes/s.html", "{% set q = get_page(path=path) %}<<{{ q.summary }}>>")
        File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
        File.write("content/a.md", "+++\ntitle = \"A\"\n+++\nSee {{ t(path=\"b.md\") }} now.\n\n<!-- more -->\n\nRest.\n")
        File.write("content/c.md", "+++\ntitle = \"C\"\n+++\nReads {{ s(path=\"a.md\") }} end.\n\n<!-- more -->\n\nRest.\n")
        File.write("content/b.md", "+++\ntitle = \"B1\"\n+++\nb\n")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/b.md"], options)

        File.write("content/b.md", "+++\ntitle = \"B2\"\n+++\nb\n")
        builder.run_incremental(["content/b.md"], options).should be_true
        File.read("public/index.html").should contain("[C::<p>Reads <<<p>See (B2) now.</p>\n>> end.</p>")
      end
    end
  end
end

describe "Builder#run_incremental version roots" do
  it "refreshes page.version.url when a translated version root stops rendering" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", <<-TOML)
          title = "T"
          base_url = "http://localhost"
          default_language = "en"
          [languages.en]
          language_name = "English"
          [languages.ko]
          language_name = "Korean"
          [[versions.list]]
          name = "v2"
          path = "docs/v2"
          latest = true
          [[versions.list]]
          name = "v1"
          path = "docs/v1"
          TOML
        FileUtils.mkdir_p("content/docs/v2")
        FileUtils.mkdir_p("content/docs/v1/guide")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ page.version.url }}")
        File.write("templates/section.html", "{{ page.version.url }}")
        File.write("content/docs/v2/_index.md", "+++\ntitle = \"v2\"\n+++\n")
        File.write("content/docs/v1/_index.md", "+++\ntitle = \"v1\"\n+++\n")
        File.write("content/docs/v1/_index.ko.md", "+++\ntitle = \"v1 ko\"\n+++\n")
        File.write("content/docs/v1/guide/_index.ko.md", "+++\ntitle = \"g\"\n+++\n")
        File.write("content/docs/v1/guide/deep.ko.md", "+++\ntitle = \"deep\"\n+++\n")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/docs/v1/_index.ko.md"], options)
        File.read("public/ko/docs/v1/guide/deep/index.html").should eq("/ko/docs/v1/")

        # The Korean root is no longer written, so every Korean v1 page
        # points at the default language's root, as a cold build does.
        File.write("content/docs/v1/_index.ko.md", "+++\ntitle = \"v1 ko\"\nrender = false\n+++\n")
        builder.run_incremental(["content/docs/v1/_index.ko.md"], options)
        File.read("public/ko/docs/v1/guide/deep/index.html").should eq("/docs/v1/")
        File.read("public/ko/docs/v1/guide/index.html").should eq("/docs/v1/")
      end
    end
  end
end

describe "Builder#run_incremental drafting a bundle" do
  it "unpublishes the bundle's [content.files] copies when a slug moved the page" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n[content.files]\nallow_extensions = ["png"]\n))
        FileUtils.mkdir_p("content/notes/p")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ page.title }}")
        File.write("content/notes/p/index.md", "+++\ntitle = \"P\"\nslug = \"sl\"\n+++\n")
        File.write("content/notes/p/img0.png", "PNG")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/notes/p/index.md"], options)
        File.exists?("public/notes/p/img0.png").should be_true
        File.exists?("public/notes/sl/img0.png").should be_true

        File.write("content/notes/p/index.md", "+++\ntitle = \"P\"\nslug = \"sl\"\ndraft = true\n+++\n")
        builder.run_incremental(["content/notes/p/index.md"], options)
        File.exists?("public/notes/sl/img0.png").should be_false
        File.exists?("public/notes/p/img0.png").should be_false
      end
    end
  end

  it "unpublishes the bundle's raw JSON and XML files" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n[content.files]\nallow_extensions = ["png"]\n))
        FileUtils.mkdir_p("content/notes/p")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ page.title }}")
        File.write("content/notes/p/index.md", "+++\ntitle = \"P\"\n+++\n")
        File.write("content/notes/p/data.json", %({"a": 1}))
        File.write("content/notes/p/feed.xml", "<x/>")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/notes/p/index.md"], options)
        File.exists?("public/notes/p/data.json").should be_true

        File.write("content/notes/p/index.md", "+++\ntitle = \"P\"\ndraft = true\n+++\n")
        builder.run_incremental(["content/notes/p/index.md"], options)
        File.exists?("public/notes/p/data.json").should be_false
        File.exists?("public/notes/p/feed.xml").should be_false
      end
    end
  end
end

describe "Builder#run_incremental image bundles" do
  it "moves a bundle's resized variants with its slug" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n[image_processing]\nenabled = true\nwidths = [16]\n))
        FileUtils.mkdir_p("content/notes/p")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ content }}")
        File.write("content/notes/p/index.md", "+++\ntitle = \"P\"\n+++\n![i](pic.png)\n")
        pixels = Bytes.new(32 * 32 * 3, 128_u8)
        LibStb.stbi_write_png("content/notes/p/pic.png", 32, 32, 3, pixels.to_unsafe.as(Void*), 32 * 3)

        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |hook| builder.register(hook) }
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/notes/p/index.md"], options)
        File.exists?("public/notes/p/pic_16w.png").should be_true

        File.write("content/notes/p/index.md", "+++\ntitle = \"P\"\nslug = \"sl\"\n+++\n![i](pic.png)\n")
        builder.run_incremental(["content/notes/p/index.md"], options)
        File.exists?("public/notes/sl/pic_16w.png").should be_true
        File.read("public/notes/sl/index.html").should contain("/notes/sl/pic_16w.png")
        File.exists?("public/notes/p/pic_16w.png").should be_false
      end
    end
  end
end

describe "Builder#run_incremental section edits" do
  it "re-renders the root listing when a top-level section turns transparent" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
        FileUtils.mkdir_p("content/posts")
        FileUtils.mkdir_p("content/other")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ page.title }}")
        File.write("templates/section.html", "{% for p in section.pages %}{{ p.title }},{% endfor %}")
        File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
        File.write("content/posts/_index.md", "+++\ntitle = \"Posts\"\n+++\n")
        File.write("content/posts/a.md", "+++\ntitle = \"A\"\ndate = 2024-01-01\n+++\n")
        # Another section, so the root index is not a neighbour of posts/a.
        File.write("content/other/_index.md", "+++\ntitle = \"Other\"\n+++\n")
        File.write("content/other/o.md", "+++\ntitle = \"O\"\ndate = 2023-01-01\n+++\n")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/posts/_index.md"], options)
        File.read("public/index.html").should contain("Posts,")

        File.write("content/posts/_index.md", "+++\ntitle = \"Posts\"\ntransparent = true\n+++\n")
        builder.run_incremental(["content/posts/_index.md"], options)
        File.read("public/index.html").should contain("A,")
        File.read("public/index.html").should_not contain("Posts,")
      end
    end
  end
end

describe "Builder#run_incremental moved link targets" do
  it "re-renders the marker summary of a page linking to a re-slugged page" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
        FileUtils.mkdir_p("content/posts")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ page.title }}")
        File.write("templates/section.html", "{% for p in section.pages %}[{{ p.summary }}]{% endfor %}")
        File.write("content/posts/_index.md", "+++\ntitle = \"Posts\"\n+++\n")
        File.write("content/posts/b.md", "+++\ntitle = \"B\"\n+++\nB\n")
        File.write("content/posts/c.md", "+++\ntitle = \"C\"\n+++\nSee [B](@/posts/b.md).\n\n<!-- more -->\n\nRest.\n")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/posts/b.md"], options)
        File.read("public/posts/index.html").should contain(%(href="/posts/b/"))

        File.write("content/posts/b.md", "+++\ntitle = \"B\"\nslug = \"bee\"\n+++\nB\n")
        builder.run_incremental(["content/posts/b.md"], options)
        File.read("public/posts/index.html").should contain(%(href="/posts/bee/"))
      end
    end
  end
end

describe "Builder#run_incremental collision loser" do
  it "unpublishes the bundle files of a page that just lost its URL" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
        FileUtils.mkdir_p("content/posts/a")
        FileUtils.mkdir_p("content/posts/x")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ page.title }}")
        File.write("content/posts/a/index.md", "+++\ntitle = \"A\"\n+++\n")
        File.write("content/posts/a/cover.png", "A-cover")
        File.write("content/posts/x/index.md", "+++\ntitle = \"X\"\n+++\n")
        File.write("content/posts/x/cover.png", "X-cover")
        File.write("content/posts/x/xonly.png", "X-only")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/posts/a/index.md"], options)
        File.exists?("public/posts/x/xonly.png").should be_true

        File.write("content/posts/a/index.md", "+++\ntitle = \"A\"\nslug = \"x\"\n+++\n")
        builder.run_incremental(["content/posts/a/index.md"], options)
        File.read("public/posts/x/cover.png").should eq("A-cover")
        File.exists?("public/posts/x/xonly.png").should be_false
      end
    end
  end
end

describe "Builder#run_incremental bundle asset URLs" do
  it "re-renders get_url(path=asset) readers when the bundle page moves" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
        FileUtils.mkdir_p("content/posts/foo")
        FileUtils.mkdir_p("content/other")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", %({{ get_url(path="posts/foo/photo.jpg") }}))
        File.write("content/posts/_index.md", "+++\ntitle = \"Posts\"\n+++\n")
        File.write("content/posts/foo/index.md", "+++\ntitle = \"Foo\"\n+++\n")
        File.write("content/posts/foo/photo.jpg", "jpg")
        # `d` sits in another section, past the bundle's reading-order
        # neighbours: nothing but the call ties it to the bundle.
        File.write("content/other/c.md", "+++\ntitle = \"C\"\n+++\n")
        File.write("content/other/d.md", "+++\ntitle = \"D\"\n+++\n")
        File.write("content/posts/e.md", "+++\ntitle = \"E\"\n+++\n")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/posts/foo/index.md"], options)
        File.read("public/other/d/index.html").should eq("http://localhost/posts/foo/photo.jpg")

        File.write("content/posts/foo/index.md", "+++\ntitle = \"Foo\"\nslug = \"moved\"\n+++\n")
        builder.run_incremental(["content/posts/foo/index.md"], options)
        File.read("public/other/d/index.html").should eq("http://localhost/posts/moved/photo.jpg")
      end
    end
  end
end

describe "Builder#run_incremental get_taxonomy and collision losers" do
  a_free = "+++\ntitle = \"A\"\ntags = [\"t1\"]\n+++\n"
  a_taking = "+++\ntitle = \"A\"\nslug = \"x\"\ntags = [\"t1\"]\n+++\n"

  # Each serve pass re-claims the output winners: get_taxonomy must follow
  # the verdict of THIS pass, both when a page starts losing its URL and
  # when a loser from the first build gets its URL back.
  [{a_free, a_taking, "[t1=1]"}, {a_taking, a_free, "[t1=1][t2=1]"}].each do |(before, after, expected)|
    it "counts only this pass's winners (#{expected})" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n[[taxonomies]]\nname = "tags"))
          FileUtils.mkdir_p("content")
          FileUtils.mkdir_p("templates")
          File.write("templates/page.html", "{{ page.title }}")
          File.write("templates/section.html", "{% for t in get_taxonomy(kind='tags').items %}[{{ t.name }}={{ t.count }}]{% endfor %}")
          File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
          File.write("content/a.md", before)
          File.write("content/b.md", "+++\ntitle = \"B\"\nslug = \"x\"\ntags = [\"t2\"]\n+++\n")

          builder = Hwaro::Core::Build::Builder.new
          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
          options.serve_mode = true
          options.preserve_output = true
          builder.run_incremental(["content/a.md"], options)

          File.write("content/a.md", after)
          builder.run_incremental(["content/a.md"], options)
          File.read("public/index.html").should eq(expected)
        end
      end
    end
  end
end

# `--stream` empties every page's source after the cold build. Serve keeps
# that page set for its incremental rebuilds, which re-render neighbours the
# edit did not re-parse — they came out with an empty body.
describe "Builder#run_incremental under --stream" do
  it "keeps the bodies of re-rendered neighbours" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
        FileUtils.mkdir_p("content/posts")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ content }}|{% if page.lower %}{{ page.lower.title }}{% endif %}")
        File.write("content/posts/a.md", "+++\ntitle = \"A\"\ndate = 2024-01-01\n+++\nbody a\n")
        File.write("content/posts/b.md", "+++\ntitle = \"B\"\ndate = 2024-01-02\n+++\nbody b\n")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, stream: true)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/posts/b.md"], options)

        # b's title moves a's `page.lower`, so a re-renders without a re-parse.
        File.write("content/posts/b.md", "+++\ntitle = \"B2\"\ndate = 2024-01-02\n+++\nbody b\n")
        builder.run_incremental(["content/posts/b.md"], options)
        File.read("public/posts/a/index.html").should eq("<p>body a</p>\n|B2")
      end
    end
  end
end

# A page dated into the future leaves the related-posts candidates even under
# --include-future; the incremental recompute skipped it and the page kept the
# list it had while published.
describe "Builder#run_incremental related posts" do
  it "clears the list of a page that turned into a future preview" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n[related]\nenabled = true\n[[taxonomies]]\nname = "tags"))
        FileUtils.mkdir_p("content/posts")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{% for r in page.related_posts %}{{ r.title }};{% endfor %}")
        File.write("content/posts/a.md", "+++\ntitle = \"A\"\ndate = 2024-01-01\ntags = [\"x\"]\n+++\n")
        File.write("content/posts/b.md", "+++\ntitle = \"B\"\ndate = 2024-01-02\ntags = [\"x\"]\n+++\n")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, include_future: true)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/posts/b.md"], options)
        File.read("public/posts/b/index.html").should eq("A;")

        File.write("content/posts/b.md", "+++\ntitle = \"B\"\ndate = 2999-01-02\ntags = [\"x\"]\n+++\n")
        builder.run_incremental(["content/posts/b.md"], options)
        File.read("public/posts/b/index.html").should eq("")
        File.read("public/posts/a/index.html").should eq("")
      end
    end
  end
end

# On a case-folding filesystem a serve pass that moves a page to a URL
# differing only by case wrote into the existing `Foo/` directory, so the dev
# server (which 404s case-mismatched paths) answered 404 for the new URL.
describe "Builder#run_incremental case-only URL change" do
  it "respells the output directory to the new URL's case" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        FileUtils.mkdir_p("probe/Case")
        pending!("needs a case-insensitive filesystem") unless Hwaro::Utils::PathUtils.case_folding_fs?(File.join(dir, "probe"))
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"))
        FileUtils.mkdir_p("content/posts")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{{ page.title }}")
        File.write("content/posts/a.md", "+++\ntitle = \"A\"\npath = \"posts/Foo\"\n+++\n")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/posts/a.md"], options)
        Dir.children("public/posts").should eq(["Foo"])

        File.write("content/posts/a.md", "+++\ntitle = \"A\"\npath = \"posts/foo\"\n+++\n")
        builder.run_incremental(["content/posts/a.md"], options)
        Dir.children("public/posts").should eq(["foo"])
        File.read("public/posts/foo/index.html").should eq("A")
      end
    end
  end
end

describe "Builder#run_incremental translation_key" do
  it "re-links the old and the new partner when an edit moves a page's key" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", <<-TOML)
          title = "T"
          base_url = "http://localhost"
          default_language = "en"
          [languages.en]
          language_name = "English"
          [languages.ko]
          language_name = "Korean"
          TOML
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{% for t in page.translations %}[{{ t.url }}]{% endfor %}")
        File.write("content/about.md", "+++\ntitle = \"About\"\ntranslation_key = \"about\"\n+++\n")
        File.write("content/old.ko.md", "+++\ntitle = \"Old\"\ntranslation_key = \"about\"\n+++\n")
        File.write("content/new.ko.md", "+++\ntitle = \"New\"\n+++\n")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        builder.run_incremental(["content/old.ko.md"], options)
        File.read("public/about/index.html").should eq("[/about/][/ko/old/]")

        # Only new.ko.md is edited: about.md and old.ko.md re-render anyway.
        File.write("content/new.ko.md", "+++\ntitle = \"New\"\ntranslation_key = \"about\"\n+++\n")
        File.write("content/old.ko.md", "+++\ntitle = \"Old\"\n+++\n")
        builder.run_incremental(["content/new.ko.md", "content/old.ko.md"], options)
        File.read("public/about/index.html").should eq("[/about/][/ko/new/]")
        File.read("public/ko/new/index.html").should eq("[/about/][/ko/new/]")
        File.read("public/ko/old/index.html").should eq("")

        # A key edit on one page alone moves the partner pair back.
        File.write("content/new.ko.md", "+++\ntitle = \"New\"\n+++\n")
        builder.run_incremental(["content/new.ko.md"], options)
        File.read("public/about/index.html").should eq("")
        File.read("public/ko/new/index.html").should eq("")
      end
    end
  end
end

describe "Builder#run_incremental translation_key collisions" do
  it "warns when an edit creates a collision, once" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", <<-TOML)
          title = "T"
          base_url = "http://localhost"
          default_language = "en"
          [languages.en]
          language_name = "English"
          [languages.ko]
          language_name = "Korean"
          TOML
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("templates/page.html", "{% for t in page.translations %}[{{ t.url }}]{% endfor %}")
        File.write("content/about.md", "+++\ntitle = \"About\"\ntranslation_key = \"about\"\n+++\n")
        File.write("content/a.ko.md", "+++\ntitle = \"A\"\ntranslation_key = \"about\"\n+++\n")
        File.write("content/b.ko.md", "+++\ntitle = \"B\"\n+++\n")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false)
        options.serve_mode = true
        options.preserve_output = true
        with_captured_log { builder.run_incremental(["content/a.ko.md"], options) }.should_not contain("translation_key")

        File.write("content/b.ko.md", "+++\ntitle = \"B\"\ntranslation_key = \"about\"\n+++\n")
        log = with_captured_log { builder.run_incremental(["content/b.ko.md"], options) }
        log.scan(%(content/b.ko.md: translation_key "about" is already used by the 'ko' page content/a.ko.md)).size.should eq(1)

        # An unrelated edit keeps the collision: no second warning.
        File.write("content/about.md", "+++\ntitle = \"About!\"\ntranslation_key = \"about\"\n+++\n")
        with_captured_log { builder.run_incremental(["content/about.md"], options) }.should_not contain("translation_key")
      end
    end
  end
end

describe "Builder#render_deferred" do
  # `--fast-start`: the cold pass runs the BeforeRender hooks (auto OG
  # images, image resize) for the priority pages only, so every listing it
  # renders sees the deferred pages without the fields those hooks fill.
  # Once the background pass has filled them, the served tree must match a
  # full build's: the priority pages re-render, and nothing reads the page
  # values cached before the hooks ran.
  it "renders every page against the fields the deferred hooks filled" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n[og.auto_image]\nenabled = true\nformat = "svg"\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
        File.write("content/new.md", "+++\ntitle = \"New\"\ndate = 2026-06-01\n+++\n")
        File.write("content/old.md", "+++\ntitle = \"Old\"\ndate = 2020-01-01\n+++\n")
        listing = "{% for p in site.pages %}[{{ p.title }}={{ p.image }}]{% endfor %}"
        File.write("templates/index.html", listing)
        File.write("templates/page.html", listing)
        File.write("templates/404.html", listing)

        builder = Hwaro::Core::Build::Builder.new
        Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, fast_start: true, fast_start_count: 1)
        options.serve_mode = true
        builder.run(options).should be_true
        builder.has_deferred_pages?.should be_true
        deferred = options.dup
        deferred.fast_start = false
        deferred.preserve_output = true
        builder.render_deferred(deferred)

        expected = "[New=/og-images/new.svg][Old=/og-images/old.svg]"
        File.read("public/index.html").should eq(expected)
        File.read("public/new/index.html").should eq(expected)
        File.read("public/old/index.html").should eq(expected)
        File.read("public/404.html").should eq(expected)
      end
    end
  end

  # `serve --fast-start --stream`: the background pass renders most of the
  # site, so it must batch and release rendered bodies like the cold pass
  # does, or `--stream`/`--memory-limit` bounded only the priority pages.
  it "streams the background pass under --stream" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
        File.write("content/new.md", "+++\ntitle = \"New\"\ndate = 2026-06-01\n+++\nnew body\n")
        File.write("content/old.md", "+++\ntitle = \"Old\"\ndate = 2020-01-01\n+++\nold body\n")
        File.write("templates/index.html", "{{ content }}")
        File.write("templates/page.html", "{{ content }}")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, stream: true, fast_start: true, fast_start_count: 1)
        options.serve_mode = true
        builder.run(options).should be_true
        deferred = options.dup
        deferred.fast_start = false
        deferred.preserve_output = true
        builder.render_deferred(deferred)

        File.read("public/old/index.html").should contain("old body")
        old = builder.site.not_nil!.pages.find! { |page| page.path == "old.md" }
        old.content.should eq("")
      end
    end
  end

  # The cold pass stashed its priority pages for the background pass even
  # when nothing was deferred (or the build was not fast-start at all), and
  # only render_deferred let go of them: the serve session kept the whole
  # first build's page set alive.
  it "holds no priority pages it will not render" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
        File.write("content/new.md", "+++\ntitle = \"New\"\ndate = 2026-06-01\n+++\n")
        File.write("content/old.md", "+++\ntitle = \"Old\"\ndate = 2020-01-01\n+++\n")
        File.write("templates/page.html", "{{ page.title }}")

        builder = Hwaro::Core::Build::Builder.new
        options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, fast_start: true, fast_start_count: 10)
        options.serve_mode = true
        builder.run(options).should be_true
        builder.has_deferred_pages?.should be_false
        builder.test_priority_pages.should be_empty

        options.fast_start_count = 1
        builder.run(options).should be_true
        builder.has_deferred_pages?.should be_true
        builder.test_priority_pages.should_not be_empty
        # A watch rebuild runs a full, non-fast-start build.
        options.fast_start = false
        builder.run(options).should be_true
        builder.test_priority_pages.should be_empty

        # A background pass that raises still lets go of them: the deferred
        # page's broken anchor fails it under broken_anchors = "error".
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n[links]\nbroken_anchors = "error"\n))
        File.write("content/old.md", "+++\ntitle = \"Old\"\ndate = 2020-01-01\n+++\n[x](@/new.md#nope)\n")
        options.fast_start = true
        builder.run(options).should be_true
        builder.test_priority_pages.should_not be_empty
        deferred = options.dup
        deferred.fast_start = false
        deferred.preserve_output = true
        expect_raises(Exception) { builder.render_deferred(deferred) }
        builder.test_priority_pages.should be_empty
      end
    end
  end

  # The cache entry of a deferred page stored the relations hash as of the
  # background pass, after the hooks filled every auto OG `image` — never
  # what the next start compares (taken before them), so under `--cache`
  # every deferred page re-rendered on every start.
  it "keeps a deferred page cached on the next --cache start" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n[og.auto_image]\nenabled = true\nformat = "svg"\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
        File.write("content/new.md", "+++\ntitle = \"New\"\ndate = 2026-06-01\n+++\n")
        File.write("content/mid.md", "+++\ntitle = \"Mid\"\ndate = 2024-01-01\n+++\n")
        File.write("content/old.md", "+++\ntitle = \"Old\"\ndate = 2020-01-01\n+++\n")
        File.write("templates/index.html", "home")
        # The neighbour's image is a relation the page's cache entry hashes.
        File.write("templates/page.html", "{% if page.lower %}{{ page.lower.image }}{% endif %}")

        session = -> do
          builder = Hwaro::Core::Build::Builder.new
          Hwaro::Content::Hooks.all.each { |hookable| builder.register(hookable) }
          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, cache: true, fast_start: true, fast_start_count: 1)
          options.serve_mode = true
          builder.run(options).should be_true
          if builder.has_deferred_pages?
            deferred = options.dup
            deferred.fast_start = false
            deferred.preserve_output = true
            builder.render_deferred(deferred)
          end
        end

        session.call
        File.read("public/old/index.html").should eq("/og-images/mid.svg")
        File.write("public/old/index.html", "untouched")
        session.call
        File.read("public/old/index.html").should eq("untouched")
      end
    end
  end

  # A fast-start `--cache` session must leave the cache describing what it
  # wrote. It never recorded the page-set fingerprint or the render-input
  # digest, so a later session whose inputs were back at an OLDER session's
  # values matched those stale keys and kept this session's pages.
  it "records the --cache keys once the deferred pages are written" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", %(title = "T"\nbase_url = "http://localhost"\n))
        FileUtils.mkdir_p("content")
        FileUtils.mkdir_p("templates")
        File.write("content/_index.md", "+++\ntitle = \"Home\"\n+++\n")
        write_post = ->(name : String, title : String, date : String) do
          File.write("content/#{name}.md", "+++\ntitle = \"#{title}\"\ndate = #{date}\n+++\n")
        end
        write_post.call("a", "A", "2020-01-01")
        write_post.call("b", "B", "2020-01-02")
        write_post.call("c", "C", "2020-01-03")
        File.write("templates/index.html", %({% for p in site.pages %}[{{ p.title }}]{% endfor %}{{ env("HWARO_SPEC_RENDER_INPUT", default="unset") }}))
        File.write("templates/page.html", "{{ page.title }}")

        session = ->(fast_start : Bool) do
          builder = Hwaro::Core::Build::Builder.new
          options = Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, cache: true, fast_start: fast_start, fast_start_count: 1)
          options.serve_mode = true
          builder.run(options).should be_true
          if fast_start
            builder.has_deferred_pages?.should be_true
            deferred = options.dup
            deferred.fast_start = false
            deferred.preserve_output = true
            builder.render_deferred(deferred)
          end
        end

        ENV["HWARO_SPEC_RENDER_INPUT"] = "one"
        session.call(false)
        File.read("public/index.html").should eq("[A][B][C]one")

        # Two edited posts: the newer one is the priority page, A is deferred.
        write_post.call("a", "A2", "2020-01-01")
        write_post.call("b", "B2", "2020-01-02")
        ENV["HWARO_SPEC_RENDER_INPUT"] = "two"
        session.call(true)
        File.read("public/index.html").should eq("[A2][B2][C]two")

        write_post.call("a", "A", "2020-01-01")
        write_post.call("b", "B", "2020-01-02")
        ENV["HWARO_SPEC_RENDER_INPUT"] = "one"
        session.call(false)
        File.read("public/index.html").should eq("[A][B][C]one")
      ensure
        ENV.delete("HWARO_SPEC_RENDER_INPUT")
      end
    end
  end
end
