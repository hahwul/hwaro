require "../spec_helper"

# SassCompiler is the build-side orchestrator for the built-in SCSS compiler
# (peer of Pipeline). The Sass language itself is covered under spec/unit/sass;
# what is pinned here is the orchestration contract: which entry files are
# picked up, which are skipped, and how compiler/filesystem failures surface as
# classified build errors rather than raw exceptions.
private def sass_config(enabled = true, minify = false) : Hwaro::Models::SassConfig
  config = Hwaro::Models::SassConfig.new
  config.enabled = enabled
  config.minify = minify
  config
end

private def static_config(exclude = [] of String) : Hwaro::Models::StaticConfig
  config = Hwaro::Models::StaticConfig.new
  config.exclude = exclude
  config
end

# Runs `compile_all` with `dir` as both the project root and the CWD, since the
# symlink guard and the importer both resolve against `Dir.current`. Paths stay
# relative — as they are in a real build — so macOS's /var -> /private/var
# symlink can't make an in-project entry look external.
private def compile_in(dir : String, config = sass_config, static = static_config, &)
  Dir.cd(dir) do
    Dir.mkdir_p("public")
    compiler = Hwaro::Assets::SassCompiler.new(config, static, "static")
    yield compiler, "public"
  end
end

describe Hwaro::Assets::SassCompiler do
  describe "#compile_all" do
    it "compiles a top-level entry to a sibling .css file" do
      Dir.mktmpdir do |dir|
        Dir.mkdir_p(File.join(dir, "static", "css"))
        File.write(File.join(dir, "static", "css", "style.scss"), "a { color: red; }")
        compile_in(dir) do |compiler, output|
          compiler.compile_all(output).should eq(1)
          File.read(File.join(output, "css", "style.css")).should contain("color: red")
        end
      end
    end

    it "returns 0 when sass is disabled" do
      Dir.mktmpdir do |dir|
        Dir.mkdir_p(File.join(dir, "static"))
        File.write(File.join(dir, "static", "a.scss"), "a { color: red; }")
        compile_in(dir, config: sass_config(enabled: false)) do |compiler, output|
          compiler.compile_all(output).should eq(0)
          File.exists?(File.join(output, "a.css")).should be_false
        end
      end
    end

    it "returns 0 when the source directory does not exist" do
      Dir.mktmpdir do |dir|
        compile_in(dir) do |compiler, output|
          compiler.compile_all(output).should eq(0)
        end
      end
    end

    # Partials are imported by entries, never compiled on their own.
    it "skips partials" do
      Dir.mktmpdir do |dir|
        Dir.mkdir_p(File.join(dir, "static"))
        File.write(File.join(dir, "static", "_vars.scss"), "$c: red;")
        File.write(File.join(dir, "static", "main.scss"), "@import 'vars'; a { color: $c; }")
        compile_in(dir) do |compiler, output|
          compiler.compile_all(output).should eq(1)
          File.exists?(File.join(output, "_vars.css")).should be_false
          File.read(File.join(output, "main.css")).should contain("red")
        end
      end
    end

    it "skips statically-excluded entries" do
      Dir.mktmpdir do |dir|
        Dir.mkdir_p(File.join(dir, "static", "vendor"))
        File.write(File.join(dir, "static", "vendor", "skip.scss"), "a { color: red; }")
        File.write(File.join(dir, "static", "keep.scss"), "b { color: blue; }")
        compile_in(dir, static: static_config(["vendor/**"])) do |compiler, output|
          compiler.compile_all(output).should eq(1)
          File.exists?(File.join(output, "vendor", "skip.css")).should be_false
          File.exists?(File.join(output, "keep.css")).should be_true
        end
      end
    end

    it "compiles nested entries preserving their relative path" do
      Dir.mktmpdir do |dir|
        Dir.mkdir_p(File.join(dir, "static", "a", "b"))
        File.write(File.join(dir, "static", "a", "b", "deep.scss"), "a { color: red; }")
        compile_in(dir) do |compiler, output|
          compiler.compile_all(output).should eq(1)
          File.exists?(File.join(output, "a", "b", "deep.css")).should be_true
        end
      end
    end

    it "minifies when configured" do
      Dir.mktmpdir do |dir|
        Dir.mkdir_p(File.join(dir, "static"))
        File.write(File.join(dir, "static", "m.scss"), "a {\n  color: red;\n}\n")
        compile_in(dir, config: sass_config(minify: true)) do |compiler, output|
          compiler.compile_all(output)
          File.read(File.join(output, "m.css")).should_not contain("\n  ")
        end
      end
    end

    # A `static/css/style.scss -> /etc/passwd` symlink would otherwise publish
    # the target's contents as CSS.
    it "skips an entry that resolves outside the project root" do
      Dir.mktmpdir do |outside|
        secret = File.join(outside, "secret.scss")
        File.write(secret, "a { color: red; }")
        Dir.mktmpdir do |dir|
          Dir.mkdir_p(File.join(dir, "static"))
          File.symlink(secret, File.join(dir, "static", "leak.scss"))
          log = with_captured_log do
            compile_in(dir) do |compiler, output|
              compiler.compile_all(output).should eq(0)
              File.exists?(File.join(output, "leak.css")).should be_false
            end
          end
          log.should contain("outside project root")
        end
      end
    end

    it "keeps an in-project symlinked entry" do
      Dir.mktmpdir do |dir|
        Dir.mkdir_p(File.join(dir, "static"))
        real = File.join(dir, "static", "real.scss")
        File.write(real, "a { color: red; }")
        File.symlink(real, File.join(dir, "static", "alias.scss"))
        compile_in(dir) do |compiler, output|
          compiler.compile_all(output).should eq(2)
        end
      end
    end

    # Full builds copy the raw sibling first and clobber it here, while a serve
    # session re-copies the raw file OVER the compiled one on edit.
    it "warns when a hand-written sibling .css occupies the same output path" do
      Dir.mktmpdir do |dir|
        Dir.mkdir_p(File.join(dir, "static"))
        File.write(File.join(dir, "static", "clash.scss"), "a { color: red; }")
        File.write(File.join(dir, "static", "clash.css"), "a { color: blue; }")
        log = with_captured_log do
          compile_in(dir) do |compiler, output|
            compiler.compile_all(output).should eq(1)
          end
        end
        log.should contain("also exists as a static source")
      end
    end

    it "raises a classified content error for a bad entry" do
      Dir.mktmpdir do |dir|
        Dir.mkdir_p(File.join(dir, "static"))
        File.write(File.join(dir, "static", "bad.scss"), "a { color: ; ")
        compile_in(dir) do |compiler, output|
          error = expect_raises(Hwaro::HwaroError) { compiler.compile_all(output) }
          error.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
        end
      end
    end
  end

  describe ".compile_source" do
    it "compiles a plain rule" do
      Hwaro::Assets::SassCompiler.compile_source("a { color: red; }", "x.scss")
        .should contain("color: red")
    end

    it "compiles nesting" do
      css = Hwaro::Assets::SassCompiler.compile_source("a { b { color: red; } }", "x.scss")
        .gsub(/\s+/, " ")
      css.should contain("a b")
    end

    it "passes plain CSS through" do
      Hwaro::Assets::SassCompiler.compile_source("a{color:red}", "x.scss").should contain("red")
    end

    it "returns empty output for empty input" do
      Hwaro::Assets::SassCompiler.compile_source("", "x.scss").strip.should eq("")
    end

    # Syntax errors must surface classified, with a path:line:col location, not
    # as a bare Sass::SyntaxError the hook manager downgrades to a generic abort.
    it "converts a syntax error into a classified content error" do
      error = expect_raises(Hwaro::HwaroError) do
        Hwaro::Assets::SassCompiler.compile_source("a { color: ; ", "broken.scss")
      end
      error.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
      error.message.not_nil!.should contain("Sass:")
    end

    it "names the failing file in the error" do
      error = expect_raises(Hwaro::HwaroError) do
        Hwaro::Assets::SassCompiler.compile_source("@mixin", "named.scss")
      end
      error.message.not_nil!.should contain("named.scss")
    end

    it "carries a fix hint" do
      error = expect_raises(Hwaro::HwaroError) do
        Hwaro::Assets::SassCompiler.compile_source("a { color: ; ", "broken.scss")
      end
      error.hint.not_nil!.should contain("features/sass")
    end

    # ELOOP / permission failures during import resolution must come out
    # classified too, not as a raw File::Error.
    it "converts a filesystem error during import resolution into a content error" do
      Dir.mktmpdir do |dir|
        Dir.cd(dir) do
          # A self-referential symlink makes the importer's stat/read fail with
          # ELOOP rather than "missing", so the File::Error rescue is the one
          # that runs. Kept in-project so the outside-root guard cannot answer
          # first and mask which branch is under test.
          File.symlink("_loop.scss", "_loop.scss")
          error = expect_raises(Hwaro::HwaroError) do
            Hwaro::Assets::SassCompiler.compile_source(%(@import "loop";), "entry.scss")
          end
          error.code.should eq(Hwaro::Errors::HWARO_E_CONTENT)
          error.message.not_nil!.should contain("filesystem error while resolving imports")
        end
      end
    end
  end
end
