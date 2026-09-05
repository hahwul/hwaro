# Sass compilation helpers shared by spec/unit/assets/sass.

# Compile one stylesheet source with the default (filesystem) loader.
def compile(scss : String, path : String = "test.scss") : String
  Hwaro::Assets::Sass.compile(scss, path)
end

# Compile `entry` out of an in-memory tree of `path => source` so
# `@import` / `@use` / `@forward` resolve without touching disk.
def compile_with(files : Hash(String, String), entry : String) : String
  loader = Hwaro::Assets::Sass::MemoryLoader.new(files)
  Hwaro::Assets::Sass.compile(files[entry], path: entry, loader: loader)
end
