# Regression specs for the 2026-09 asset-lane hunt.
#
# Every expectation here was taken from dart-sass 1.103 output for the
# same source, not from reading our own implementation.

require "../../spec_helper"
require "file_utils"

private def compile(source : String) : String
  Hwaro::Assets::Sass.compile(source)
end

private def with_sass_tree(files : Hash(String, String), &)
  dir = File.tempname("hwaro-sass-hunt")
  Dir.mkdir_p(dir)
  begin
    files.each do |rel, body|
      path = File.join(dir, rel)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, body)
    end
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

describe "Sass @import of a forwarding partial" do
  # `components/_index.scss` that only `@forward`s its partials is the
  # standard index-file layout; reaching it through the classic `@import`
  # spelling left every forwarded member undefined.
  it "exposes members a @forward'ed index partial re-exports" do
    with_sass_tree({
      "components/_index.scss"  => %(@forward "button";\n@forward "card";\n),
      "components/_button.scss" => %($btn-pad: 4px;\n@mixin btn { color: red; }\n@function twice($x) { @return $x * 2; }\n),
      "components/_card.scss"   => %($card-pad: 8px;\n),
      "entry.scss"              => %(@import "components";\n.z { padding: $btn-pad; margin: $card-pad; width: twice(3px); @include btn; }\n),
    }) do |dir|
      css = Hwaro::Assets::Sass.compile(File.read(File.join(dir, "entry.scss")),
        path: File.join(dir, "entry.scss"), root: dir)
      css.should contain("padding: 4px")
      css.should contain("margin: 8px")
      css.should contain("width: 6px")
      css.should contain("color: red")
    end
  end

  it "leaves private members behind the module boundary" do
    with_sass_tree({
      "lib/_index.scss" => %(@forward "vars";\n),
      "lib/_vars.scss"  => %($-secret: 1px;\n$public: 2px;\n),
      "entry.scss"      => %(@import "lib";\n.z { a: $public; }\n),
    }) do |dir|
      css = Hwaro::Assets::Sass.compile(File.read(File.join(dir, "entry.scss")),
        path: File.join(dir, "entry.scss"), root: dir)
      css.should contain("a: 2px")
    end
  end
end

describe "Sass interpolation of lists" do
  # dart-sass renders strings UNQUOTED at every nesting level inside
  # `#{...}`; keeping the quotes shipped `content: ""a", "b""`.
  it "unquotes string members of a computed list" do
    compile(%(.y { content: "\#{("a" "b")}"; })).should contain(%(content: "a b";))
  end

  it "unquotes string members of a stored list" do
    compile(%($l: ("a", "b");\n.x { content: "\#{$l}"; })).should contain(%(content: "a, b";))
  end

  it "unquotes a stored list substituted into a value" do
    compile(%($l: ("a", "b");\n.z { font-family: \#{$l}; })).should contain("font-family: a, b;")
  end

  it "still unquotes a lone string" do
    compile(%(.w { content: \#{"solo"}; })).should contain("content: solo;")
  end

  it "leaves an unquoted list untouched" do
    compile(%($l: (a, b);\n.x { content: "\#{$l}"; })).should contain(%(content: "a, b";))
  end

  it "keeps quotes outside interpolation" do
    compile(%($l: ("a", "b");\n.x { content: $l; })).should contain(%(content: "a", "b";))
  end
end

describe "Sass sass:map" do
  it "supports map.deep-remove" do
    css = compile(%(@use "sass:map";\n$m: (a: (b: 1, c: 2));\n.x { content: "\#{map.deep-remove($m, a, b)}"; }))
    css.should contain("(a: (c: 2))")
  end

  it "removes a top-level key with a single-key path" do
    css = compile(%(@use "sass:map";\n.x { content: "\#{map.deep-remove((a: 1, b: 2), a)}"; }))
    css.should contain("(b: 2)")
  end

  it "leaves the map untouched when the path misses" do
    css = compile(%(@use "sass:map";\n.x { content: "\#{map.deep-remove((a: 1), zz, yy)}"; }))
    css.should contain(%(content: "(a: 1)";))
    css.should_not contain("map.deep-remove")
  end
end

describe "Sass color.hwb" do
  it "accepts the separate-argument spelling" do
    compile(%(@use "sass:color";\n.x { color: color.hwb(210, 20%, 30%); })).should contain("color: #3373b3")
  end

  it "accepts keyword arguments" do
    compile(%(@use "sass:color";\n.x { color: color.hwb($hue: 210, $whiteness: 20%, $blackness: 30%); }))
      .should contain("color: #3373b3")
  end

  it "still accepts the single space-separated channels list" do
    compile(%(@use "sass:color";\n.x { color: color.hwb(210 20% 30%); })).should contain("color: #3373b3")
  end
end

describe "review follow-ups on #773 built-ins" do
  it "accepts color.hwb with a fourth alpha argument, positional or keyword" do
    compile(%(@use "sass:color";\no { c: color.hwb(210, 20%, 30%, 0.5); })).should contain("c: rgba(51, 115, 179, 0.5);")
    compile(%(@use "sass:color";\no { c: color.hwb(210, 20%, 30%, $alpha: 0.5); })).should contain("c: rgba(51, 115, 179, 0.5);")
    compile(%(@use "sass:color";\no { c: color.hwb($hue: 0, $whiteness: 0%, $blackness: 0%); })).should contain("c: red;")
  end

  it "accepts map.deep-remove keyword arguments" do
    css = compile(%(@use "sass:map";\n$m: (a: (b: 1, c: 2), d: 3);\n.x { content: "\#{map.deep-remove($map: $m, $key: a)}"; }))
    css.should contain(%(content: "(d: 3)";))
    css.should_not contain("map.deep-remove")
  end
end
