require "./version_files"

if version = report_versions
  puts "All versions match: #{version}"
else
  exit 1
end
