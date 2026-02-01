require "file_utils"
require "option_parser"

# Generate dummy content
def generate_content(count : Int32, force : Bool)
  benchmark_dir = "benchmark"
  content_dir = File.join(benchmark_dir, "content")
  templates_dir = File.join(benchmark_dir, "templates")

  if Dir.exists?(content_dir)
    if force
      FileUtils.rm_rf(content_dir)
    else
      puts "Error: '#{content_dir}' directory already exists. Use --force to overwrite."
      exit 1
    end
  end
  FileUtils.mkdir_p(File.join(content_dir, "benchmark"))

  count.times do |i|
    File.write(File.join(content_dir, "benchmark", "page_#{i}.md"), <<-MD
      +++
      title = "Benchmark Page #{i}"
      date = "2024-01-01"
      +++

      # Page #{i}

      This is a benchmark page.
      MD
    )
  end

  # Create a template that iterates over all pages to stress-test the variable construction
  if Dir.exists?(templates_dir)
    if force
      FileUtils.rm_rf(templates_dir)
    else
      puts "Error: '#{templates_dir}' directory already exists. Use --force to overwrite."
      exit 1
    end
  end
  FileUtils.mkdir_p(templates_dir)
  File.write(File.join(templates_dir, "default.html"), <<-HTML
    <!DOCTYPE html>
    <html>
    <head><title>{{ page.title }}</title></head>
    <body>
      <h1>{{ page.title }}</h1>
      {{ content }}

      <h2>All Pages</h2>
      <ul>
      {% for p in site.pages %}
        <li><a href="{{ p.url }}">{{ p.title }}</a></li>
      {% endfor %}
      </ul>
    </body>
    </html>
    HTML
  )

  # Copy config.toml to benchmark directory
  if File.exists?("config.toml")
    FileUtils.cp("config.toml", File.join(benchmark_dir, "config.toml"))
  else
    # Create a minimal config.toml if not exists
    File.write(File.join(benchmark_dir, "config.toml"), <<-TOML
      title = "Benchmark Site"
      description = "Benchmark site for testing"
      base_url = "http://localhost:3000"
      TOML
    )
  end
end

# Run build
def run_build
  puts "Building hwaro..."
  status = Process.run("shards", ["build", "--release"], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
  unless status.success?
    puts "Build failed"
    exit 1
  end

  Dir.cd("benchmark") do
    puts "Running hwaro build..."
    start_time = Time.instant
    status = Process.run("../bin/hwaro", ["build"], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
    end_time = Time.instant

    if status.success?
      puts "Build time: #{(end_time - start_time).total_seconds}s"
    else
      puts "Hwaro build failed"
      exit 1
    end
  end
end

count = 1000
force = false
OptionParser.parse do |parser|
  parser.on("-c COUNT", "--count=COUNT", "Number of pages") { |c| count = c.to_i }
  parser.on("-f", "--force", "Overwrite content and templates directories") { force = true }
end

# Create benchmark directory
FileUtils.mkdir_p("benchmark")

generate_content(count, force)
run_build

# Clean up benchmark directory
FileUtils.rm_rf("benchmark")
