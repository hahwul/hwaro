require "../support/build_helper"

# =============================================================================
# Automatic summary fallback — end-to-end through Builder#run.
#
# `page.summary` precedence: `<!-- more -->` marker > `description` >
# automatic body excerpt (`[content] summary_length`, default 70 words).
# The excerpt is cut from the RENDERED body so shortcodes, code blocks and
# headings cannot leak; it ships as one escaped `<p>` so the existing
# `{{ p.summary | safe }}` idiom keeps working.
# =============================================================================

private AUTO_TEMPLATES = {
  "index.html"          => "{% for p in site.pages %}[{{ p.title }}={{ p.summary | safe }}|{{ p.summary_truncated }}]{% endfor %}",
  "page.html"           => "{{ content }}",
  "section.html"        => "{{ content }}",
  "shortcodes/tag.html" => %(<span class="tag">SC-{{ name }}</span>),
}

private HOME_MD = "---\ntitle: Home\n---\nHome body"

private def auto_config(extra : String = "") : String
  <<-TOML
    title = "Auto Summary"
    base_url = "http://localhost"
    #{extra}
    TOML
end

private def words(n : Int32, prefix : String = "w") : String
  (1..n).map { |i| "#{prefix}#{i}" }.join(' ')
end

describe "Automatic summary fallback" do
  it "fills page.summary from the rendered body when no marker or description exists" do
    content = {
      "index.md"      => HOME_MD,
      "posts/long.md" => "+++\ntitle = \"Long\"\n+++\n\n#{words(80)}\n",
    }
    build_site(auto_config("[content]\nsummary_length = 10"), content_files: content, template_files: AUTO_TEMPLATES) do
      listing = File.read("public/index.html")
      listing.should contain("[Long=<p>#{words(10)}…</p>|true]")
      listing.should_not contain("w11")
    end
  end

  it "does not append the ellipsis when the body already fits" do
    content = {"index.md" => HOME_MD, "posts/short.md" => "+++\ntitle = \"Short\"\n+++\n\nJust five little words here.\n"}
    build_site(auto_config, content_files: content, template_files: AUTO_TEMPLATES) do
      File.read("public/index.html").should contain("[Short=<p>Just five little words here.</p>|false]")
    end
  end

  it "lets a <!-- more --> marker and a description win over the excerpt" do
    content = {
      "index.md"        => HOME_MD,
      "posts/marker.md" => "+++\ntitle = \"Marker\"\n+++\n\nLEAD from marker.\n\n<!-- more -->\n\n#{words(50)}\n",
      "posts/desc.md"   => "+++\ntitle = \"Desc\"\ndescription = \"FM description\"\n+++\n\n#{words(50)}\n",
    }
    build_site(auto_config("[content]\nsummary_length = 5"), content_files: content, template_files: AUTO_TEMPLATES) do
      listing = File.read("public/index.html")
      listing.should contain("[Marker=<p>LEAD from marker.</p>\n|false]")
      listing.should contain("[Desc=FM description|false]")
      listing.should_not contain("w1 w2 w3 w4 w5…")
    end
  end

  it "renders shortcodes and drops code blocks, headings and images from the excerpt" do
    body = <<-MD
      # Page Heading

      Intro {{ tag(name="alpha") }} paragraph & more.

      ```crystal
      puts "CODE"
      ```

      ![alt text](/img.png)

      Trailing `inline` prose here.
      MD
    content = {"index.md" => HOME_MD, "posts/rich.md" => "+++\ntitle = \"Rich\"\n+++\n\n#{body}\n"}
    build_site(auto_config, content_files: content, template_files: AUTO_TEMPLATES) do
      listing = File.read("public/index.html")
      listing.should contain("[Rich=<p>Intro SC-alpha paragraph &amp; more. Trailing prose here.</p>|false]")
      %w[Page\ Heading CODE alt\ text tag(name inline].each { |leak| listing.should_not contain(leak) }
    end
  end

  it "measures CJK-dominant text in characters (length × 2)" do
    korean = "가나다라마바사아자차카타파하" * 4 # 56 chars, no spaces
    content = {"index.md" => HOME_MD, "posts/ko.md" => "+++\ntitle = \"KO\"\n+++\n\n#{korean}\n"}
    build_site(auto_config("[content]\nsummary_length = 10"), content_files: content, template_files: AUTO_TEMPLATES) do
      File.read("public/index.html").should contain("[KO=<p>#{korean[0, 20]}…</p>|true]")
    end
  end

  it "summary_length = 0 disables the fallback entirely" do
    content = {"index.md" => HOME_MD, "posts/off.md" => "+++\ntitle = \"Off\"\n+++\n\n#{words(80)}\n"}
    build_site(auto_config("[content]\nsummary_length = 0"), content_files: content, template_files: AUTO_TEMPLATES) do
      File.read("public/index.html").should contain("[Off=|false]")
    end
  end

  it "honours a custom summary_ellipsis" do
    content = {"index.md" => HOME_MD, "posts/e.md" => "+++\ntitle = \"E\"\n+++\n\n#{words(20)}\n"}
    build_site(auto_config("[content]\nsummary_length = 3\nsummary_ellipsis = \" [more]\""), content_files: content, template_files: AUTO_TEMPLATES) do
      File.read("public/index.html").should contain("[E=<p>w1 w2 w3 [more]</p>|true]")
    end
  end

  it "feeds the excerpt into og:description when there is no description" do
    templates = AUTO_TEMPLATES.merge({"page.html" => "{{ og_all_tags }}{{ content }}"})
    content = {"index.md" => HOME_MD, "posts/og.md" => "+++\ntitle = \"OG\"\n+++\n\nOpen graph excerpt sentence.\n"}
    build_site(auto_config, content_files: content, template_files: templates) do
      File.read("public/posts/og/index.html").should contain(%(property="og:description" content="Open graph excerpt sentence."))
    end
  end
end

# `build --cache`: the excerpt is derived from body + config, so both a body
# edit and a `[content]` summary setting change must re-render listings.
private def run_cached(cache : Bool)
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, cache: cache))
end

private def write_auto_project(summary_length : Int32, body : String)
  File.write("config.toml", auto_config("[content]\nsummary_length = #{summary_length}"))
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  File.write("content/index.md", "---\ntitle: Home\n---\nHome")
  File.write("templates/index.html", "{% for p in site.pages %}[{{ p.summary | safe }}]{% endfor %}")
  File.write("templates/page.html", "{{ content }}")
  File.write("templates/section.html", "{{ content }}")
  File.write("content/posts/a.md", "+++\ntitle = \"A\"\n+++\n\n#{body}\n")
end

describe "Automatic summary under --cache" do
  it "re-renders listings when summary_length changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_auto_project(3, words(10))
        run_cached(true)
        File.read("public/index.html").should contain("[<p>w1 w2 w3…</p>]")

        write_auto_project(5, words(10))
        run_cached(true)
        warm = File.read("public/index.html")
        warm.should contain("[<p>w1 w2 w3 w4 w5…</p>]")

        FileUtils.rm_rf("public")
        FileUtils.rm_rf(".hwaro_cache.json")
        run_cached(false)
        File.read("public/index.html").should eq(warm)
      end
    end
  end

  it "re-renders listings when a body edit changes the excerpt" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_auto_project(3, words(10, "old"))
        run_cached(true)
        File.read("public/index.html").should contain("old1 old2 old3…")

        sleep 1.1.seconds
        write_auto_project(3, words(10, "new"))
        run_cached(true)
        warm = File.read("public/index.html")
        warm.should contain("new1 new2 new3…")
        warm.should_not contain("old1")

        FileUtils.rm_rf("public")
        FileUtils.rm_rf(".hwaro_cache.json")
        run_cached(false)
        File.read("public/index.html").should eq(warm)
      end
    end
  end
end
