# Sass compilation helpers shared by spec/unit/assets/sass.

# Compile one stylesheet source with the default (filesystem) loader.
def compile(scss : String, path : String = "test.scss") : String
  Hwaro::Assets::Sass.compile(scss, path)
end

# Compile `entry` out of a tree of `path => source` written into a temp
# project root, so `@import` / `@use` / `@forward` resolve like real files.
def compile_with(files : Hash(String, String), entry : String) : String
  Dir.mktmpdir do |dir|
    files.each do |path, content|
      full = File.join(dir, path)
      Dir.mkdir_p(File.dirname(full))
      File.write(full, content)
    end
    Hwaro::Assets::Sass.compile(files[entry], path: entry, root: dir)
  end
end
