require "./support/build_helper"

# =============================================================================
# Template dependency tracking
#
# A static extends/include/import graph over templates lets a template edit
# invalidate only the pages that actually render it — in cached builds (per
# page closure hashes in .hwaro_cache.json) and in serve re-renders
# (run_rerender renders only affected pages). Any statically unresolvable
# reference makes the graph dynamic and restores whole-site invalidation.
# =============================================================================

private def make_builder
  builder = Hwaro::Core::Build::Builder.new
  Hwaro::Content::Hooks.all.each { |h| builder.register(h) }
  builder
end

private def run_build(builder, cache : Bool = false)
  builder.run(output_dir: "public", parallel: false, cache: cache, highlight: false, verbose: false, profile: false)
end

private def write_dep_site
  File.write("config.toml", BASIC_CONFIG)
  FileUtils.mkdir_p("content")
  FileUtils.mkdir_p("templates/partials")
  FileUtils.mkdir_p("templates/shortcodes")
  File.write("templates/base.html", "<html><body>{% block main %}{% endblock %}</body></html>")
  File.write("templates/page.html", "{% extends \"base.html\" %}\n{% block main %}PAGE {{ content }}{% endblock %}")
  File.write("templates/special.html", "{% extends \"base.html\" %}\n{% block main %}SPECIAL {{ content }}{% include \"partials/footer.html\" %}{% endblock %}")
  File.write("templates/partials/footer.html", "<footer>v1</footer>")
  File.write("templates/shortcodes/badge.html", "<span>B1</span>")
  File.write("content/normal.md", "+++\ntitle = \"Normal\"\n+++\nnormal body")
  File.write("content/special.md", "+++\ntitle = \"Special\"\ntemplate = \"special\"\n+++\nspecial body")
  File.write("content/badged.md", "+++\ntitle = \"Badged\"\n+++\nhas {{ badge() }} inline")
end

describe "TemplateDeps graph" do
  it "resolves extends/include/import references and transitive closures" do
    templates = {
      "base"            => "<html>{% block m %}{% endblock %}</html>",
      "page"            => "{% extends \"base.html\" %}",
      "special"         => "{% extends 'base.html' %}{% include \"partials/footer.html\" %}",
      "partials/footer" => "{% from \"macros.html\" import thing %}",
      "macros"          => "{% macro thing() %}x{% endmacro %}",
    }
    deps = Hwaro::Core::Build::TemplateDeps.new(templates)

    deps.dynamic?.should be_false
    deps.closure("page").should eq(Set{"page", "base"})
    deps.closure("special").should eq(Set{"special", "base", "partials/footer", "macros"})
  end

  it "marks the graph dynamic for non-literal references" do
    deps = Hwaro::Core::Build::TemplateDeps.new({"dyn" => "{% include some_var %}"})
    deps.dynamic?.should be_true
  end

  it "reports dependents of a changed template" do
    templates = {
      "base"  => "x",
      "page"  => "{% extends \"base.html\" %}",
      "other" => "y",
    }
    deps = Hwaro::Core::Build::TemplateDeps.new(templates)
    affected = deps.dependents_closure(Set{"base"})
    affected.should contain("base")
    affected.should contain("page")
    affected.should_not contain("other")
  end

  it "changes the closure hash when a dependency changes" do
    v1 = Hwaro::Core::Build::TemplateDeps.new({"page" => "{% include \"a.html\" %}", "a" => "one"})
    v2 = Hwaro::Core::Build::TemplateDeps.new({"page" => "{% include \"a.html\" %}", "a" => "two"})
    unrelated = Hwaro::Core::Build::TemplateDeps.new({"page" => "{% include \"a.html\" %}", "a" => "one", "b" => "zzz"})

    v1.closure_hash("page").should_not eq(v2.closure_hash("page"))
    v1.closure_hash("page").should eq(unrelated.closure_hash("page"))
  end

  it "detects shortcode usage in content" do
    deps = Hwaro::Core::Build::TemplateDeps.new({"shortcodes/badge" => "<b>x</b>", "page" => "y"})
    deps.shortcodes_used_in("has {{ badge() }} inline").should eq(Set{"shortcodes/badge"})
    deps.shortcodes_used_in("no shortcode here").should be_empty
  end

  it "terminates with a finite closure on a circular template reference" do
    # A user can author a circular extends (a→b, b→a) by mistake. The
    # closure DFS relies on `result.add?` to break the cycle; a regression
    # to a plain `<<` would loop forever and hang the build. Pin termination
    # and finiteness.
    deps = Hwaro::Core::Build::TemplateDeps.new({
      "a" => %({% extends "b.html" %}),
      "b" => %({% extends "a.html" %}),
    })

    deps.closure("a").should eq(Set{"a", "b"})

    hash = deps.closure_hash("a")
    hash.should_not be_empty
    hash.size.should eq(32)

    affected = deps.dependents_closure(Set{"a"})
    affected.should contain("a")
    affected.should contain("b")
  end
end

describe "Template deps: cached builds" do
  it "rebuilds only pages whose template closure includes the edited partial" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_dep_site
        run_build(make_builder, cache: true)
        normal_mtime = File.info("public/normal/index.html").modification_time

        File.write("templates/partials/footer.html", "<footer>v2</footer>")
        run_build(make_builder, cache: true)

        File.read("public/special/index.html").should contain("v2")
        File.info("public/normal/index.html").modification_time.should eq(normal_mtime)
      end
    end
  end

  it "rebuilds only pages whose content uses an edited shortcode" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_dep_site
        run_build(make_builder, cache: true)
        normal_mtime = File.info("public/normal/index.html").modification_time

        File.write("templates/shortcodes/badge.html", "<span>B2</span>")
        run_build(make_builder, cache: true)

        File.read("public/badged/index.html").should contain("B2")
        File.info("public/normal/index.html").modification_time.should eq(normal_mtime)
      end
    end
  end

  it "falls back to rebuilding everything when a dynamic include exists" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_dep_site
        File.write("templates/dyn.html", "{% include some_var %}")
        run_build(make_builder, cache: true)
        normal_mtime = File.info("public/normal/index.html").modification_time

        sleep 10.milliseconds
        File.write("templates/partials/footer.html", "<footer>v2</footer>")
        run_build(make_builder, cache: true)

        File.info("public/normal/index.html").modification_time.should_not eq(normal_mtime)
      end
    end
  end

  it "falls back to rebuilding everything when build.template_deps = false" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_dep_site
        File.write("config.toml", "#{BASIC_CONFIG}\n[build]\ntemplate_deps = false\n")
        run_build(make_builder, cache: true)
        normal_mtime = File.info("public/normal/index.html").modification_time

        sleep 10.milliseconds
        File.write("templates/partials/footer.html", "<footer>v2</footer>")
        run_build(make_builder, cache: true)

        File.info("public/normal/index.html").modification_time.should_not eq(normal_mtime)
      end
    end
  end
end

describe "Template deps: serve re-render (run_rerender)" do
  it "re-renders only affected pages on a partial edit" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_dep_site
        builder = make_builder
        run_build(builder)
        normal_mtime = File.info("public/normal/index.html").modification_time

        File.write("templates/partials/footer.html", "<footer>v2</footer>")
        builder.run_rerender(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false))

        File.read("public/special/index.html").should contain("v2")
        File.info("public/normal/index.html").modification_time.should eq(normal_mtime)
      end
    end
  end

  it "re-renders nothing when template contents are unchanged" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_dep_site
        builder = make_builder
        run_build(builder)
        special_mtime = File.info("public/special/index.html").modification_time

        sleep 10.milliseconds
        FileUtils.touch("templates/partials/footer.html")
        builder.run_rerender(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false))

        File.info("public/special/index.html").modification_time.should eq(special_mtime)
      end
    end
  end

  it "re-renders everything when the template set changes" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_dep_site
        builder = make_builder
        run_build(builder)
        normal_mtime = File.info("public/normal/index.html").modification_time

        sleep 10.milliseconds
        File.write("templates/brand-new.html", "<p>new</p>")
        builder.run_rerender(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false))

        File.info("public/normal/index.html").modification_time.should_not eq(normal_mtime)
      end
    end
  end

  it "re-renders the base template's dependents transitively" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_dep_site
        builder = make_builder
        run_build(builder)

        File.write("templates/base.html", "<html><body class=\"v2\">{% block main %}{% endblock %}</body></html>")
        builder.run_rerender(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false))

        File.read("public/normal/index.html").should contain("class=\"v2\"")
        File.read("public/special/index.html").should contain("class=\"v2\"")
      end
    end
  end
end

describe "Template deps: review regressions" do
  it "marks concatenation includes dynamic instead of recording a partial literal" do
    deps = Hwaro::Core::Build::TemplateDeps.new({"dyn" => %({% include "partials/" ~ name %})})
    deps.dynamic?.should be_true
  end

  it "keeps literal references with tag keywords static" do
    templates = {
      "a" => %({% include "x.html" ignore missing %}),
      "b" => %({% include "x.html" with context %}),
      "c" => %({% import "macros.html" as m %}),
      "d" => %({% from "macros.html" import thing with context %}),
      "x" => "x", "macros" => "m",
    }
    deps = Hwaro::Core::Build::TemplateDeps.new(templates)
    deps.dynamic?.should be_false
    deps.closure("a").should contain("x")
    deps.closure("c").should contain("macros")
    deps.closure("d").should contain("macros")
  end

  it "detects all three shortcode invocation syntaxes" do
    deps = Hwaro::Core::Build::TemplateDeps.new({"shortcodes/badge" => "<b>x</b>"})
    deps.shortcodes_used_in("a {{ badge() }} b").should eq(Set{"shortcodes/badge"})
    deps.shortcodes_used_in(%(a {{ shortcode("badge", color="x") }} b)).should eq(Set{"shortcodes/badge"})
    deps.shortcodes_used_in(%(a {% badge type="x" %}body{% end %} b)).should eq(Set{"shortcodes/badge"})
  end

  it "records an include edge when no space follows the include keyword" do
    templates = {
      "page"            => %({% include"partials/banner.html" %}),
      "partials/banner" => "<div>banner</div>",
    }
    deps = Hwaro::Core::Build::TemplateDeps.new(templates)

    deps.dynamic?.should be_false
    deps.dependents_closure(Set{"partials/banner"}).should contain("page")
  end

  it "detects explicit shortcode() calls with a space before the paren" do
    deps = Hwaro::Core::Build::TemplateDeps.new({"shortcodes/alert" => "<b>!</b>"})
    deps.shortcodes_used_in(%(a {{ shortcode ("alert", msg="hi") }} b)).should contain("shortcodes/alert")
  end

  it "rebuilds a page using explicit shortcode() syntax when the shortcode changes (cached)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_dep_site
        File.write("content/explicit.md", "+++\ntitle = \"Explicit\"\n+++\nhas {{ shortcode(\"badge\") }} inline")
        run_build(make_builder, cache: true)

        File.write("templates/shortcodes/badge.html", "<span>B2</span>")
        run_build(make_builder, cache: true)

        File.read("public/explicit/index.html").should contain("B2")
      end
    end
  end

  it "content+template changes together re-render the content page (run_incremental_then_rerender)" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        write_dep_site
        builder = make_builder
        run_build(builder)

        # Edit a content file AND an unrelated template in the same batch.
        # The selective re-render must not skip the content-changed page.
        File.write("content/normal.md", "+++\ntitle = \"Normal\"\n+++\nUPDATED body")
        File.write("templates/partials/footer.html", "<footer>v2</footer>")
        builder.run_incremental_then_rerender(["content/normal.md"],
          Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false))

        File.read("public/normal/index.html").should contain("UPDATED body")
        File.read("public/special/index.html").should contain("v2")
      end
    end
  end

  it "content+template changes keep cascaded values on the re-parsed page" do
    Dir.mktmpdir do |dir|
      Dir.cd(dir) do
        File.write("config.toml", BASIC_CONFIG)
        FileUtils.mkdir_p("content/blog")
        FileUtils.mkdir_p("templates/partials")
        File.write("templates/page.html", "<p>banner={{ page.extra.banner | default(\"none\") }} {{ content }}</p>{% include \"partials/footer.html\" %}")
        File.write("templates/section.html", "<p>section</p>")
        File.write("templates/partials/footer.html", "<footer>v1</footer>")
        File.write("content/blog/_index.md", "+++\ntitle = \"Blog\"\n\n[cascade.extra]\nbanner = \"inherited.png\"\n+++")
        File.write("content/blog/post.md", "+++\ntitle = \"Post\"\n+++\nbody")

        builder = make_builder
        run_build(builder)
        File.read("public/blog/post/index.html").should contain("banner=inherited.png")

        File.write("content/blog/post.md", "+++\ntitle = \"Post\"\n+++\nUPDATED body")
        File.write("templates/partials/footer.html", "<footer>v2</footer>")
        builder.run_incremental_then_rerender(["content/blog/post.md"],
          Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, highlight: false))

        html = File.read("public/blog/post/index.html")
        html.should contain("UPDATED body")
        html.should contain("banner=inherited.png")
        html.should contain("v2")
      end
    end
  end
end
