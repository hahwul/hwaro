require "file_utils"
require "option_parser"

# Generates a deterministic benchmark site and times `hwaro build` against it.
#
# Two corpus shapes are supported (--shape):
#
#   harsh (default) — exercises the real render hot paths rather than a
#   trivial flat site: multiple sections with _index.md, fenced code blocks
#   (server-mode highlighting), a user shortcode, tags (taxonomies), TOC
#   pages, and internal @/ links, plus a template that iterates both
#   section.pages and site.pages.
#
#   public — mirrors the public ssg-benchmark corpus
#   (github.com/hahwul/ssg-benchmark): lorem-ipsum prose with four headings,
#   no code fences, no shortcodes, no internal links, a single posts section,
#   tags ["benchmark", "test"] on every page, the benchmark's minimal
#   templates (page.html references only page.title/tags/content), and a
#   config that disables highlight/search/sitemap/robots/llms/feeds. Use this
#   shape to reproduce what https://hahwul.github.io/ssg-benchmark/ measures.
#
# Generation is fully deterministic — same --count and --shape always produce
# byte-identical input, so output trees can be diffed across code changes.
#
# Usage:
#   crystal run scripts/benchmark_run.cr -- --count 1000 --force --keep --runs 5
#   crystal run scripts/benchmark_run.cr -- --shape=public --count 5000 --runs 5
#   crystal run scripts/benchmark_run.cr -- --generate-only --dir /tmp/bench-site

SECTIONS  = 8
TAG_POOL  = ["crystal", "performance", "web", "ssg", "testing", "tooling"]
LANGUAGES = ["crystal", "bash", "javascript"]

def code_block(i : Int32) : String
  lang = LANGUAGES[i % LANGUAGES.size]
  case lang
  when "crystal"
    <<-CODE
      ```crystal
      # Shared example used across many pages
      def greet(name : String) : String
        "Hello, \#{name}!"
      end

      puts greet("page #{i}")
      ```
      CODE
  when "bash"
    <<-CODE
      ```bash
      # Shared example used across many pages
      set -euo pipefail
      echo "building page #{i}"
      hwaro build --minify
      ```
      CODE
  else
    <<-CODE
      ```javascript
      // Shared example used across many pages
      const pages = document.querySelectorAll("article");
      console.log(`page #{i}: ${pages.length} articles`);
      ```
      CODE
  end
end

def page_body(i : Int32, count : Int32) : String
  target = (i + 37) % count
  String.build do |io|
    io << "## Overview\n\n"
    io << "This is benchmark page #{i}. It contains enough prose to make "
    io << "markdown rendering non-trivial, including *emphasis*, **strong** "
    io << "text, `inline code`, and a [link](https://example.com/#{i}).\n\n"
    io << "See also [page #{target}](@/section-#{target % SECTIONS}/page_#{target}.md).\n\n"
    io << "## Details\n\n"
    io << "- First point about topic #{i % 13}\n"
    io << "- Second point referencing item #{i % 7}\n"
    io << "- Third point with `code_span_#{i % 5}`\n\n"
    if i % 10 < 3
      io << code_block(i) << "\n\n"
    end
    if i % 10 == 3
      io << "{{ note() }}\n\n"
    end
    io << "## Conclusion\n\n"
    io << "Closing paragraph for page #{i} with a bit more text so the page "
    io << "is not degenerate.\n"
  end
end

def front_matter(i : Int32) : String
  tags = [TAG_POOL[i % TAG_POOL.size], TAG_POOL[(i + 2) % TAG_POOL.size]]
  toc = i % 5 == 0
  String.build do |io|
    io << "+++\n"
    io << "title = \"Benchmark Page #{i}\"\n"
    io << "date = \"2024-#{sprintf("%02d", (i % 12) + 1)}-#{sprintf("%02d", (i % 28) + 1)}\"\n"
    io << "tags = [#{tags.map(&.inspect).join(", ")}]\n"
    if toc
      io << "toc = true\n"
      io << "insert_anchor_links = true\n"
    end
    io << "+++\n"
  end
end

# Paragraph pool copied from the public benchmark's generate-content.sh so
# the prose profile (sentence length, punctuation density) matches what the
# published numbers measure. Selection is deterministic, unlike the bash
# script's $RANDOM, so corpora stay diffable.
PUBLIC_PARAGRAPHS = [
  "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
  "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
  "Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae dicta sunt explicabo.",
  "Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos qui ratione voluptatem sequi nesciunt.",
  "Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet, consectetur, adipisci velit, sed quia non numquam eius modi tempora incidunt ut labore et dolore magnam aliquam quaerat voluptatem.",
  "Ut enim ad minima veniam, quis nostrum exercitationem ullam corporis suscipit laboriosam, nisi ut aliquid ex ea commodi consequatur?",
  "Quis autem vel eum iure reprehenderit qui in ea voluptate velit esse quam nihil molestiae consequatur, vel illum qui dolorem eum fugiat quo voluptas nulla pariatur?",
  "At vero eos et accusamus et iusto odio dignissimos ducimus qui blanditiis praesentium voluptatum deleniti atque corrupti quos dolores et quas molestias excepturi sint occaecati cupiditate non provident.",
]

PUBLIC_TITLES = [
  "Getting Started with Static Sites",
  "Performance Optimization Tips",
  "Building Modern Websites",
  "Understanding Build Systems",
  "Content Management Strategies",
  "Web Development Best Practices",
  "Deployment Automation Guide",
  "Template Engine Comparison",
  "Asset Pipeline Configuration",
  "SEO for Static Sites",
]

def public_paragraphs(i : Int32, block : Int32) : String
  n = 3 + ((i + block) % 5)
  String.build do |io|
    n.times do |p|
      io << PUBLIC_PARAGRAPHS[(i + block * 3 + p) % PUBLIC_PARAGRAPHS.size]
      io << "\n\n"
    end
  end
end

def public_page(i : Int32) : String
  title = "#{PUBLIC_TITLES[i % PUBLIC_TITLES.size]} - Part #{i}"
  date = "2024-#{sprintf("%02d", (i % 12) + 1)}-#{sprintf("%02d", (i % 28) + 1)}"
  String.build do |io|
    io << "+++\n"
    io << "title = \"#{title}\"\n"
    io << "date = \"#{date}\"\n"
    io << "\n"
    io << "[taxonomies]\n"
    io << "tags = [\"benchmark\", \"test\"]\n"
    io << "+++\n\n"
    io << "# #{title}\n\n"
    io << public_paragraphs(i, 0)
    io << "## Section One\n\n"
    io << public_paragraphs(i, 1)
    io << "## Section Two\n\n"
    io << public_paragraphs(i, 2)
    io << "## Conclusion\n\n"
    io << PUBLIC_PARAGRAPHS[i % PUBLIC_PARAGRAPHS.size] << "\n"
  end
end

def generate_content_public(site_dir : String, count : Int32)
  content_dir = File.join(site_dir, "content", "posts")
  templates_dir = File.join(site_dir, "templates")
  FileUtils.mkdir_p(content_dir)
  FileUtils.mkdir_p(templates_dir)

  count.times do |i|
    File.write(File.join(content_dir, "post-#{i + 1}.md"), public_page(i + 1))
  end

  # Templates copied from ssg-benchmark's sites/hwaro/templates — the page
  # template touches only page.title/date/tags/description and content; no
  # section.pages / site.pages iteration and no SEO variables.
  File.write(File.join(templates_dir, "base.html"), <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>{% block title %}{{ site.title }}{% endblock %}</title>
        <meta name="description" content="{{ site.description }}">
    </head>
    <body>
        <main>
            {% block content %}{% endblock %}
        </main>
    </body>
    </html>
    HTML
  )
  File.write(File.join(templates_dir, "index.html"), <<-HTML
    {% extends "base.html" %}

    {% block content %}
    <section class="home">
        <h1>{{ site.title }}</h1>
        <ul class="posts-list">
        {% for page in pages | slice(end=10) %}
            <li><a href="{{ page.permalink }}">{{ page.title }}</a></li>
        {% endfor %}
        </ul>
    </section>
    {% endblock %}
    HTML
  )
  File.write(File.join(templates_dir, "page.html"), <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>{{ page.title }} | {{ site.title }}</title>
        <meta name="description" content="{{ page.description | default(value=site.description) }}">
    </head>
    <body>
        <main>
            <article>
                <header>
                    <h1>{{ page.title }}</h1>
                    {% if page.date %}
                    <time datetime="{{ page.date }}">{{ page.date }}</time>
                    {% endif %}
                    {% if page.tags %}
                    <div class="tags">
                        {% for tag in page.tags %}
                        <span class="tag">{{ tag }}</span>
                        {% endfor %}
                    </div>
                    {% endif %}
                </header>
                <div class="content">
                    {{ content }}
                </div>
            </article>
        </main>
    </body>
    </html>
    HTML
  )
  File.write(File.join(templates_dir, "section.html"), <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>{{ section.title }} - {{ site.title }}</title>
    </head>
    <body>
        <main>
            <section>
                <h1>{{ section.title }}</h1>
                <ul class="posts-list">
                {% for page in section.pages %}
                    <li><a href="{{ page.permalink }}">{{ page.title }}</a></li>
                {% endfor %}
                </ul>
            </section>
        </main>
    </body>
    </html>
    HTML
  )

  File.write(File.join(site_dir, "config.toml"), <<-TOML
    title = "SSG Benchmark Site"
    description = "Benchmark site for testing SSG performance"
    base_url = "http://example.com"

    [plugins]
    processors = ["markdown"]

    [highlight]
    enabled = false

    [search]
    enabled = false

    [pagination]
    enabled = false

    [[taxonomies]]
    name = "tags"
    feed = false
    sitemap = false

    [sitemap]
    enabled = false

    [robots]
    enabled = false

    [llms]
    enabled = false

    [feeds]
    enabled = false

    [markdown]
    safe = false

    [auto_includes]
    enabled = false
    TOML
  )
end

def generate_content(site_dir : String, count : Int32, force : Bool, shape : String)
  content_dir = File.join(site_dir, "content")
  templates_dir = File.join(site_dir, "templates")

  [content_dir, templates_dir].each do |dir|
    if Dir.exists?(dir)
      if force
        FileUtils.rm_rf(dir)
      else
        puts "Error: '#{dir}' directory already exists. Use --force to overwrite."
        exit 1
      end
    end
  end

  if shape == "public"
    generate_content_public(site_dir, count)
    return
  end

  SECTIONS.times do |s|
    section_dir = File.join(content_dir, "section-#{s}")
    FileUtils.mkdir_p(section_dir)
    File.write(File.join(section_dir, "_index.md"), <<-MD
      +++
      title = "Section #{s}"
      description = "Benchmark section #{s}"
      +++

      Index of benchmark section #{s}.
      MD
    )
  end

  count.times do |i|
    path = File.join(content_dir, "section-#{i % SECTIONS}", "page_#{i}.md")
    File.write(path, front_matter(i) + "\n" + page_body(i, count))
  end

  FileUtils.mkdir_p(File.join(templates_dir, "shortcodes"))
  File.write(File.join(templates_dir, "base.html"), <<-HTML
    <!DOCTYPE html>
    <html>
    <head><title>{% block title %}Benchmark{% endblock %}</title></head>
    <body>
      {% block body %}{% endblock %}
    </body>
    </html>
    HTML
  )
  # Iterating over all pages stress-tests template variable construction.
  File.write(File.join(templates_dir, "default.html"), <<-HTML
    {% extends "base.html" %}
    {% block title %}{{ page.title }}{% endblock %}
    {% block body %}
      <h1>{{ page.title }}</h1>
      {{ content }}

      <h2>Section Pages</h2>
      <ul>
      {% for p in section.pages %}
        <li><a href="{{ p.url }}">{{ p.title }}</a></li>
      {% endfor %}
      </ul>

      <h2>All Pages</h2>
      <ul>
      {% for p in site.pages %}
        <li><a href="{{ p.url }}">{{ p.title }}</a></li>
      {% endfor %}
      </ul>
    {% endblock %}
    HTML
  )
  File.write(File.join(templates_dir, "shortcodes", "note.html"), <<-HTML
    <div class="note"><strong>Note:</strong> benchmark shortcode body.</div>
    HTML
  )

  File.write(File.join(site_dir, "config.toml"), <<-TOML
    title = "Benchmark Site"
    description = "Benchmark site for hwaro performance testing"
    base_url = "http://localhost:3000"

    [[taxonomies]]
    name = "tags"

    [search]
    enabled = true

    [highlight]
    mode = "server"
    TOML
  )
end

def compile_hwaro
  puts "Building hwaro (release, parity with shipped binaries)..."
  # Same flags as .github/workflows/release-binary.yml so measurements
  # reflect what users actually run.
  status = Process.run("shards", ["build", "--release", "--no-debug", "-Dpreview_mt"],
    output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
  unless status.success?
    puts "Build failed"
    exit 1
  end
end

def run_builds(site_dir : String, runs : Int32, build_args : Array(String), verbose : Bool)
  hwaro_bin = File.expand_path("bin/hwaro")
  times = [] of Float64

  Dir.cd(site_dir) do
    runs.times do |run|
      output = verbose ? Process::Redirect::Inherit : Process::Redirect::Close
      start_time = Time.instant
      status = Process.run(hwaro_bin, ["build"] + build_args, output: output, error: Process::Redirect::Inherit)
      elapsed = (Time.instant - start_time).total_seconds

      unless status.success?
        puts "Hwaro build failed (run #{run + 1})"
        exit 1
      end
      times << elapsed
      puts "Run #{run + 1}: #{elapsed.round(3)}s"
    end
  end

  if times.size >= 3
    # Discard the first run (FS warm-up), report the median of the rest.
    steady = times[1..].sort
    median = steady[steady.size // 2]
    puts "Median of runs 2..#{times.size}: #{median.round(3)}s"
  end
end

count = 5000
force = false
keep = false
runs = 1
skip_compile = false
generate_only = false
verbose = false
site_dir = "benchmark"
build_args = [] of String
shape = "harsh"

OptionParser.parse do |parser|
  parser.on("-c COUNT", "--count=COUNT", "Number of pages (default 5000)") { |c| count = c.to_i }
  parser.on("--shape=SHAPE", "Corpus shape: harsh (default) or public") do |s|
    unless {"harsh", "public"}.includes?(s)
      puts "Error: unknown shape '#{s}' (expected harsh or public)"
      exit 1
    end
    shape = s
  end
  parser.on("-f", "--force", "Overwrite existing content/templates") { force = true }
  parser.on("-k", "--keep", "Keep the site directory after the run") { keep = true }
  parser.on("-d DIR", "--dir=DIR", "Site directory (default ./benchmark)") { |d| site_dir = d }
  parser.on("-r RUNS", "--runs=RUNS", "Timed build runs (default 1)") { |r| runs = r.to_i }
  parser.on("-s", "--skip-compile", "Reuse existing bin/hwaro") { skip_compile = true }
  parser.on("-g", "--generate-only", "Generate the corpus and exit") { generate_only = true }
  parser.on("-v", "--verbose", "Show hwaro build output") { verbose = true }
  parser.on("--build-args=ARGS", "Extra args for `hwaro build` (space-separated)") { |a| build_args = a.split(' ', remove_empty: true) }
end

FileUtils.mkdir_p(site_dir)
generate_content(site_dir, count, force, shape)
puts "Generated #{count} pages in #{site_dir}/ (shape: #{shape})"
exit 0 if generate_only

compile_hwaro unless skip_compile
run_builds(site_dir, runs, build_args, verbose)

FileUtils.rm_rf(site_dir) unless keep
