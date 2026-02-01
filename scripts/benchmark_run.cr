require "file_utils"
require "option_parser"

# Generate dummy content
def generate_content(count : Int32, force : Bool)
  if Dir.exists?("content")
    if force
      FileUtils.rm_rf("content")
    else
      puts "Error: 'content' directory already exists. Use --force to overwrite."
      exit 1
    end
  end
  FileUtils.mkdir_p("content/benchmark")

  count.times do |i|
    File.write("content/benchmark/page_#{i}.md", <<-MD
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
  if Dir.exists?("templates")
    if force
      FileUtils.rm_rf("templates")
    else
      puts "Error: 'templates' directory already exists. Use --force to overwrite."
      exit 1
    end
  end
  FileUtils.mkdir_p("templates")
  File.write("templates/default.html", <<-HTML
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
end

# Run build
def run_build
  puts "Building hwaro..."
  status = Process.run("shards", ["build", "--release"], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
  unless status.success?
    puts "Build failed"
    exit 1
  end

  puts "Running hwaro build..."
  start_time = Time.instant
  status = Process.run("./bin/hwaro", ["build"], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
  end_time = Time.instant

  if status.success?
    puts "Build time: #{(end_time - start_time).total_seconds}s"
  else
    puts "Hwaro build failed"
    exit 1
  end
end

count = 1000
force = false
OptionParser.parse do |parser|
  parser.on("-c COUNT", "--count=COUNT", "Number of pages") { |c| count = c.to_i }
  parser.on("-f", "--force", "Overwrite content and templates directories") { force = true }
end

generate_content(count, force)
run_build
