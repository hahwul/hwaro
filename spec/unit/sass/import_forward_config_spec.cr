require "../../spec_helper"
require "../../../src/assets/sass"
require "file_utils"

# `@import` of a sheet that `@forward`s modules: the importing file's
# globals configure the forwarded modules' `!default` variables (dart-sass
# "implicit configuration"), and the members land in the importing SCOPE.
#
# Regression guard for the fix in #773: binding the forwarded members into
# the importer's root after loading the module unconfigured overwrote the
# importer's own `$btn-pad: 99px` with the module's `8px !default` — the
# classic "set the variables, then @import the library" pattern lost its
# overrides. Every expectation here was verified against dart-sass 1.103.

private def with_sass_tree(files : Hash(String, String), &)
  dir = File.tempname("hwaro-sass-import-config")
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

private def compile_entry(files : Hash(String, String)) : String
  with_sass_tree(files) do |dir|
    entry = File.join(dir, "entry.scss")
    return Hwaro::Assets::Sass.compile(File.read(entry), path: entry, root: dir)
  end
end

private FORWARDING_INDEX = {
  "components/_index.scss"  => %(@forward "button";\n),
  "components/_button.scss" => %($btn-pad: 8px !default;\n$btn-pad2: $btn-pad * 2 !default;\n@mixin btn { padding: $btn-pad; }\n),
}

describe "Sass @import of a forwarding partial: importer globals configure !default" do
  it "keeps a global the importer set before the import (the override pattern)" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "entry.scss" => %($btn-pad: 99px;\n@import "components";\n.z { padding: $btn-pad; @include btn; }\n),
    }))
    css.should contain("padding: 99px;\n  padding: 99px;")
    css.should_not contain("8px")
  end

  it "feeds the configured value into derived !default declarations" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "entry.scss" => %($btn-pad: 10px;\n@import "components";\n.z { padding: $btn-pad $btn-pad2; }\n),
    }))
    css.should contain("padding: 10px 20px;")
  end

  it "still takes the module default when the importer set nothing" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "entry.scss" => %(@import "components";\n.z { padding: $btn-pad $btn-pad2; }\n),
    }))
    css.should contain("padding: 8px 16px;")
  end

  it "does not let an importer global override an unguarded module assignment" do
    css = compile_entry({
      "components/_index.scss"  => %(@forward "button";\n),
      "components/_button.scss" => %($btn-pad: 8px;\n),
      "entry.scss"              => %($btn-pad: 99px;\n@import "components";\n.z { padding: $btn-pad; }\n),
    })
    css.should contain("padding: 8px;")
  end

  it "treats a null importer global as unset" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "entry.scss" => %($btn-pad: null;\n@import "components";\n.z { padding: $btn-pad; }\n),
    }))
    css.should contain("padding: 8px;")
  end

  it "strips a forward prefix before configuring the module" do
    css = compile_entry({
      "components/_index.scss"  => %(@forward "button" as btn-*;\n),
      "components/_button.scss" => %($pad: 8px !default;\n@mixin box { padding: $pad; }\n),
      "entry.scss"              => %($btn-pad: 99px;\n@import "components";\n.z { @include btn-box; }\n),
    })
    css.should contain("padding: 99px;")
  end

  it "does not configure a variable the forward hides" do
    css = compile_entry({
      "components/_index.scss"  => %(@forward "button" hide $pad;\n),
      "components/_button.scss" => %($pad: 8px !default;\n@mixin box { padding: $pad; }\n),
      "entry.scss"              => %($pad: 99px;\n@import "components";\n.z { @include box; }\n),
    })
    css.should contain("padding: 8px;")
  end

  it "passes the configuration through a chain of forwards" do
    css = compile_entry({
      "lib/_index.scss"       => %(@forward "inner";\n),
      "lib/inner/_index.scss" => %(@forward "vars";\n),
      "lib/inner/_vars.scss"  => %($size: 1px !default;\n),
      "entry.scss"            => %($size: 77px;\n@import "lib";\n.z { width: $size; }\n),
    })
    css.should contain("width: 77px;")
  end

  it "never configures a module the imported sheet reaches through @use" do
    css = compile_entry({
      "lib/_index.scss" => %(@use "vars";\n.lib { width: vars.$size; }\n),
      "lib/_vars.scss"  => %($size: 1px !default;\n),
      "entry.scss"      => %($size: 77px;\n@import "lib";\n.z { width: $size; }\n),
    })
    css.should contain(".lib {\n  width: 1px;")
    css.should contain(".z {\n  width: 77px;")
  end

  it "silently keeps an already-loaded module's configuration" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "entry.scss" => %(@use "components/button" with ($btn-pad: 5px);\n@import "components";\n.z { padding: $btn-pad; }\n),
    }))
    css.should contain("padding: 5px;")
  end

  it "does not reconfigure on a second import after the importer reassigned the variable" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "entry.scss" => %(@import "components";\n$btn-pad: 42px;\n@import "components";\n.z { padding: $btn-pad; }\n),
    }))
    css.should contain("padding: 42px;")
  end

  it "configures from the enclosing module's globals when the import sits inside a @use'd module" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "_theme.scss" => %($btn-pad: 33px;\n@import "components";\n.m { padding: $btn-pad; }\n),
      "entry.scss"  => %(@use "theme";\n.z { padding: theme.$btn-pad; }\n),
    }))
    css.should contain(".m {\n  padding: 33px;")
    css.should contain(".z {\n  padding: 33px;")
  end
end

describe "Sass @import of a forwarding partial: members bind into the importing scope" do
  it "scopes members of a nested import to the enclosing block" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "entry.scss" => %(.wrap { @import "components"; .z { padding: $btn-pad; @include btn; } }\n),
    }))
    css.should contain(".wrap .z {\n  padding: 8px;\n  padding: 8px;")
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /undefined variable/) do
      compile_entry(FORWARDING_INDEX.merge({
        "entry.scss" => %(.wrap { @import "components"; }\n.after { padding: $btn-pad; }\n),
      }))
    end
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /undefined mixin/) do
      compile_entry(FORWARDING_INDEX.merge({
        "entry.scss" => %(.wrap { @import "components"; }\n.after { @include btn; }\n),
      }))
    end
  end

  it "shadows an importer global inside the block without touching it outside" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "entry.scss" => %($btn-pad: 50px;\n.wrap { @import "components"; .z { padding: $btn-pad; } }\n.after { padding: $btn-pad; }\n),
    }))
    css.should contain(".wrap .z {\n  padding: 50px;")
    css.should contain(".after {\n  padding: 50px;")
  end
end

# Review follow-up on #778: the import used to diff the module-wide staging
# maps before/after, so a SECOND import of the same forwarding index (another
# block, a second @include, root after nested, or after the importer's own
# @forward of the partial) saw "nothing new" and bound nothing — undefined
# variable/mixin on valid Sass. The implicit configuration also read only the
# root scope, so a block-local override was overwritten by the module default.
describe "Sass @import of a forwarding partial: repeated imports and nested scopes" do
  it "binds the forwarded members again when a second block imports the same index" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "entry.scss" => %(.wrap { @import "components"; }\n.other { @import "components"; padding: $btn-pad; @include btn; }\n),
    }))
    css.should contain(".other {\n  padding: 8px;\n  padding: 8px;")
  end

  it "binds at the root after the same index was imported inside a block" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "entry.scss" => %(.wrap { @import "components"; }\n@import "components";\n.z { padding: $btn-pad; }\n),
    }))
    css.should contain(".z {\n  padding: 8px;")
  end

  it "binds on every @include of a mixin that imports the index" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "entry.scss" => %(@mixin wrap { @import "components"; padding: $btn-pad; }\n.z { @include wrap; }\n.y { @include wrap; }\n),
    }))
    css.should contain(".z {\n  padding: 8px;")
    css.should contain(".y {\n  padding: 8px;")
  end

  it "binds after the importer already @forward-ed the same partial" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "entry.scss" => %(@forward "components/button";\n@import "components";\n.z { padding: $btn-pad; }\n),
    }))
    css.should contain(".z {\n  padding: 8px;")
  end

  it "configures the forwarded module from a block-local variable" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "entry.scss" => %(.wrap { $btn-pad: 99px; @import "components"; .z { padding: $btn-pad; @include btn; } }\n),
    }))
    css.should contain("padding: 99px;\n  padding: 99px;")
    css.should_not contain("8px")
  end

  it "lets the innermost scope win over a global for the implicit configuration" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "entry.scss" => %($btn-pad: 99px;\n.wrap { $btn-pad: 50px; @import "components"; .z { padding: $btn-pad; } }\n),
    }))
    css.should contain("padding: 50px;")
  end

  it "does not re-export members a nested @import forwarded inside a @use-d module" do
    files = FORWARDING_INDEX.merge({
      "_theme.scss" => %(.m { @import "components"; padding: $btn-pad; }\n),
      "entry.scss"  => %(@use "theme";\n.z { padding: theme.$btn-pad; }\n),
    })
    expect_raises(Hwaro::Assets::Sass::SyntaxError, /btn-pad/) { compile_entry(files) }
  end

  it "still re-exports members a root-level @import forwarded inside a @use-d module" do
    css = compile_entry(FORWARDING_INDEX.merge({
      "_theme.scss" => %(@import "components";\n),
      "entry.scss"  => %(@use "theme";\n.z { padding: theme.$btn-pad; }\n),
    }))
    css.should contain(".z {\n  padding: 8px;")
  end
end
