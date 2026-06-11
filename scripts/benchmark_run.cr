require "file_utils"
require "option_parser"

# Generates a deterministic benchmark site and times `hwaro build` against it.
#
# The corpus is designed to exercise the real render hot paths rather than a
# trivial flat site: multiple sections with _index.md, fenced code blocks
# (server-mode highlighting), a user shortcode, tags (taxonomies), TOC pages,
# and internal @/ links. Generation is fully deterministic — same --count
# always produces byte-identical input, so output trees can be diffed across
# code changes.
#
# Usage:
#   crystal run scripts/benchmark_run.cr -- --count 1000 --force --keep --runs 5
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

def generate_content(site_dir : String, count : Int32, force : Bool)
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

OptionParser.parse do |parser|
  parser.on("-c COUNT", "--count=COUNT", "Number of pages (default 5000)") { |c| count = c.to_i }
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
generate_content(site_dir, count, force)
puts "Generated #{count} pages in #{site_dir}/"
exit 0 if generate_only

compile_hwaro unless skip_compile
run_builds(site_dir, runs, build_args, verbose)

FileUtils.rm_rf(site_dir) unless keep
