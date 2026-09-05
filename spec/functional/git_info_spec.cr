require "../support/build_helper"

# =============================================================================
# `[git] enabled = true` end-to-end: a real repository is created in the temp
# project, content is committed with fixed author dates, and the build must
# expose `page.git`, fall back `updated` (and optionally `date`) to the
# commit history, and carry that through sitemap/feeds/JSON-LD. Also pins
# the --cache contract: a new commit to an unedited file re-renders it.
# =============================================================================

# `[git]` is the LAST table so tests can append keys to it.
private GIT_CONFIG = <<-TOML
  title = "Git Site"
  base_url = "https://example.com"

  [sitemap]
  enabled = true

  [feeds]
  enabled = true
  type = "atom"

  [git]
  enabled = true
  TOML

private PAGE_TEMPLATE = <<-HTML
  {{ page.title }}|updated={{ page.updated }}|date={{ page.date }}|git={% if page.git %}{{ page.git.short_hash }},{{ page.git.hash }},{{ page.git.author_name }},{{ page.git.author_email }},{{ page.git.lastmod | date(format="%Y-%m-%d %H:%M") }},{{ page.git.first_commit | date(format="%Y-%m-%d") }}{% else %}none{% endif %}
  {{ jsonld }}
  HTML

private LIST_TEMPLATE = <<-HTML
  {% for p in section.pages %}{{ p.title }}:{{ p.updated }}:{% if p.git %}{{ p.git.short_hash }}{% else %}none{% endif %};{% endfor %}
  HTML

private def git(*args : String, env : Hash(String, String)? = nil) : String
  stdout = IO::Memory.new
  stderr = IO::Memory.new
  argv = ["-c", "user.name=Spec Author", "-c", "user.email=spec@example.com", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"] + args.to_a
  status = Process.run("git", argv, env: env, output: stdout, error: stderr)
  raise "git #{args.join(" ")} failed: #{stderr}" unless status.success?
  stdout.to_s
end

private def commit_all(message : String, date : String, author : String = "Spec Author", email : String = "spec@example.com") : String
  git("add", "-A")
  git("commit", "-q", "-m", message, env: {
    "GIT_AUTHOR_DATE"    => date,
    "GIT_COMMITTER_DATE" => date,
    "GIT_AUTHOR_NAME"    => author,
    "GIT_AUTHOR_EMAIL"   => email,
  })
  git("rev-parse", "HEAD").strip
end

private def write_git_project(config : String = GIT_CONFIG)
  File.write("config.toml", config)
  FileUtils.mkdir_p("content/posts")
  FileUtils.mkdir_p("templates")
  File.write("templates/index.html", "HOME")
  File.write("templates/page.html", PAGE_TEMPLATE)
  File.write("templates/section.html", LIST_TEMPLATE)
  File.write("content/posts/_index.md", "+++\ntitle = \"Posts\"\n+++\n")
  File.write("content/posts/committed.md", "+++\ntitle = \"Committed\"\n+++\nbody")
  File.write("content/posts/dated.md", "+++\ntitle = \"Dated\"\ndate = \"2020-01-01\"\nupdated = \"2021-02-03\"\n+++\nbody")
  git("init", "-q")
end

private def run_build(cache : Bool = false) : Bool
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
  builder.run(Hwaro::Config::Options::BuildOptions.new(
    output_dir: "public", parallel: false, highlight: false, cache: cache))
end

describe "[git] page metadata" do
  it "exposes page.git and falls back updated to the latest commit" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_git_project
        first = commit_all("first", "2024-01-10T09:00:00+00:00", "First Author", "first@example.com")
        File.write("content/posts/committed.md", "+++\ntitle = \"Committed\"\n+++\nbody v2")
        second = commit_all("second", "2024-03-05T14:30:00+00:00", "Second Author", "second@example.com")

        run_build.should be_true

        html = File.read("public/posts/committed/index.html")
        html.should contain("updated=2024-03-05")
        # `date` is NOT filled by default (use_date = false).
        html.should contain("|date=|")
        html.should contain("git=#{second[0, 7]},#{second},Second Author,second@example.com,2024-03-05 14:30,2024-01-10")
        # JSON-LD dateModified follows page.updated.
        html.should contain(%("dateModified":"2024-03-05T14:30:00+00:00"))

        # Front matter always wins over the git fallback, but page.git is still there.
        dated = File.read("public/posts/dated/index.html")
        dated.should contain("updated=2021-02-03|date=2020-01-01|git=#{first[0, 7]}")

        # Sitemap lastmod / feed updated pick the git-derived `updated` up.
        sitemap = File.read("public/sitemap.xml")
        sitemap.should match(/<loc>https:\/\/example\.com\/posts\/committed\/<\/loc>\s*<lastmod>2024-03-05<\/lastmod>/)
        feed = File.read("public/atom.xml")
        feed.should contain("<updated>2024-03-05T14:30:00")

        # Listings (section.pages) see the same fields.
        listing = File.read("public/posts/index.html")
        listing.should contain("Committed:2024-03-05:#{second[0, 7]};")
      end
    end
  end

  it "fills date from the first commit when use_date = true" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_git_project(GIT_CONFIG + "\nuse_date = true\n")
        commit_all("first", "2024-01-10T09:00:00+00:00")
        File.write("content/posts/committed.md", "+++\ntitle = \"Committed\"\n+++\nbody v2")
        commit_all("second", "2024-03-05T14:30:00+00:00")

        run_build.should be_true
        html = File.read("public/posts/committed/index.html")
        html.should contain("updated=2024-03-05|date=2024-01-10|")
        html.should contain(%("datePublished":"2024-01-10T09:00:00+00:00"))
        # An explicit front-matter date still wins.
        File.read("public/posts/dated/index.html").should contain("date=2020-01-01|")
      end
    end
  end

  it "leaves updated untouched when use_lastmod = false" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_git_project(GIT_CONFIG + "\nuse_lastmod = false\n")
        sha = commit_all("first", "2024-01-10T09:00:00+00:00")
        run_build.should be_true
        html = File.read("public/posts/committed/index.html")
        html.should contain("|updated=|date=|git=#{sha[0, 7]}")
        File.read("public/sitemap.xml").should_not contain("<lastmod>2024-01-10")
      end
    end
  end

  it "gives uncommitted files no git info and no fallback" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_git_project
        commit_all("first", "2024-01-10T09:00:00+00:00")
        File.write("content/posts/new.md", "+++\ntitle = \"New\"\n+++\nnot committed")
        run_build.should be_true
        File.read("public/posts/new/index.html").should contain("New|updated=|date=|git=none")
        File.read("public/posts/committed/index.html").should contain("updated=2024-01-10")
      end
    end
  end

  it "keys page bundles and translations by their own markdown file" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_git_project(GIT_CONFIG.sub("[git]\nenabled = true", "[languages.ko]\nname = \"Korean\"\n\n[git]\nenabled = true"))
        FileUtils.mkdir_p("content/posts/bundle")
        File.write("content/posts/bundle/index.md", "+++\ntitle = \"Bundle\"\n+++\nbody")
        File.write("content/posts/bundle/photo.txt", "asset")
        File.write("content/posts/committed.ko.md", "+++\ntitle = \"Committed KO\"\n+++\nbody")
        commit_all("first", "2024-01-10T09:00:00+00:00")
        File.write("content/posts/committed.ko.md", "+++\ntitle = \"Committed KO\"\n+++\nbody v2")
        ko = commit_all("ko only", "2024-05-01T09:00:00+00:00")
        File.write("content/posts/bundle/photo.txt", "asset v2")
        commit_all("asset only", "2024-06-01T09:00:00+00:00")

        run_build.should be_true
        # The translation has its own history; the default-language file does not move.
        File.read("public/ko/posts/committed/index.html").should contain("updated=2024-05-01|date=|git=#{ko[0, 7]}")
        File.read("public/posts/committed/index.html").should contain("updated=2024-01-10")
        # Bundle keyed by index.md: touching only an asset does not move lastmod.
        File.read("public/posts/bundle/index.html").should contain("updated=2024-01-10")
      end
    end
  end

  it "warns once and builds normally when the site is not a git repository" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_git_project
        FileUtils.rm_rf(".git")
        log = with_captured_log { run_build.should be_true }
        log.should contain("not inside a git repository")
        log.scan("not inside a git repository").size.should eq(1)
        File.read("public/posts/committed/index.html").should contain("updated=|date=|git=none")
      end
    end
  end

  it "keeps page.git nil when [git] is disabled" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_git_project(GIT_CONFIG.sub("[git]\nenabled = true", "[git]\nenabled = false"))
        commit_all("first", "2024-01-10T09:00:00+00:00")
        log = with_captured_log { run_build.should be_true }
        log.should_not contain("[git]")
        File.read("public/posts/committed/index.html").should contain("Committed|updated=|date=|git=none")
        # Only the front-matter `updated` of dated.md reaches the sitemap.
        File.read("public/sitemap.xml").should_not contain("<lastmod>2024-01-10")
      end
    end
  end

  it "re-renders an unedited page under --cache when a new commit moves its lastmod" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_git_project
        commit_all("first", "2024-01-10T09:00:00+00:00")
        run_build(cache: true).should be_true
        File.read("public/posts/committed/index.html").should contain("updated=2024-01-10")
        cold_listing = File.read("public/posts/index.html")

        # Warm no-op rebuild: nothing moved, output is identical.
        run_build(cache: true).should be_true
        File.read("public/posts/committed/index.html").should contain("updated=2024-01-10")

        # Rewrite history so the file's latest commit changes WITHOUT touching
        # its bytes (amend the date) — only the git fingerprint moves.
        git("commit", "-q", "--amend", "--no-edit", "--date", "2024-08-20T08:00:00+00:00", env: {
          "GIT_COMMITTER_DATE" => "2024-08-20T08:00:00+00:00",
        })
        run_build(cache: true).should be_true
        File.read("public/posts/committed/index.html").should contain("updated=2024-08-20")
        # The section listing depends on the page set, which the commit moved.
        File.read("public/posts/index.html").should_not eq(cold_listing)
        File.read("public/posts/index.html").should contain("Committed:2024-08-20:")
        File.read("public/sitemap.xml").should contain("<lastmod>2024-08-20</lastmod>")
      end
    end
  end
end
