require "../../../spec_helper"
require "../../../support/build_helper"
require "../../../../src/content/processors/syntax_highlighter"
require "../../../../src/content/processors/includes"

private CUSTOM_GRAMMAR = <<-'XML'
  <lexer>
    <config>
      <name>MyDSL</name>
      <alias>mydsl</alias>
      <alias>MDSL</alias>
    </config>
    <rules>
      <state name="root">
        <rule pattern="#.*$"><token type="CommentSingle"/></rule>
        <rule pattern="\b(let|emit)\b"><token type="Keyword"/></rule>
        <rule pattern="\s+"><token type="Text"/></rule>
        <rule pattern="."><token type="Text"/></rule>
      </state>
    </rules>
  </lexer>
  XML

# A grammar that takes over the bundled `ini` alias.
private INI_OVERRIDE = <<-'XML'
  <lexer>
    <config><name>MyIni</name><alias>ini</alias></config>
    <rules><state name="root"><rule pattern="[\s\S]"><token type="Keyword"/></rule></state></rules>
  </lexer>
  XML

private def lexers_config(dir : String? = "lexers", mode : String = "server") : Hwaro::Models::Config
  config = Hwaro::Models::Config.new
  config.highlight.lexers_dir = dir
  config.highlight.mode = mode
  config
end

# Every example leaves the process with no custom grammars registered, so
# the rest of the suite highlights with the bundled lexers only.
private def with_lexers(files : Hash(String, String), &)
  Dir.mktmpdir do |dir|
    Dir.cd(dir) do
      FileUtils.mkdir_p("lexers")
      files.each { |name, body| File.write(File.join("lexers", name), body) }
      yield
    end
  end
ensure
  Hwaro::Content::Processors::CustomLexers.apply(Hwaro::Models::Config.new)
end

private def server_highlight(code : String, lang : String) : String?
  Hwaro::Content::Processors::ServerHighlighter.highlight(code, lang)
end

describe Hwaro::Content::Processors::CustomLexers do
  it "registers a grammar under its name and aliases, case-insensitively" do
    with_lexers({"mydsl.xml" => CUSTOM_GRAMMAR}) do
      digest = Hwaro::Content::Processors::CustomLexers.apply(lexers_config)
      digest.should_not be_empty
      %w[mydsl MyDSL mdsl MDSL].each do |lang|
        server_highlight("let x # c", lang).should eq(%(<span class="hljs-keyword">let</span> x <span class="hljs-comment"># c</span>))
      end
    end
  end

  it "lets a custom alias override a bundled lexer" do
    bundled = server_highlight("[core]\nname = x\n", "ini")
    with_lexers({"ini.xml" => INI_OVERRIDE}) do
      Hwaro::Content::Processors::CustomLexers.apply(lexers_config)
      server_highlight("[core]\nname = x\n", "ini").should_not eq(bundled)
      server_highlight("a", "ini").should eq(%(<span class="hljs-keyword">a</span>))
    end
    # Unregistering restores the bundled lexer (and forgets the memo).
    server_highlight("[core]\nname = x\n", "ini").should eq(bundled)
  end

  it "re-highlights a language that had no lexer once a grammar appears" do
    server_highlight("let", "mydsl").should be_nil
    with_lexers({"mydsl.xml" => CUSTOM_GRAMMAR}) do
      Hwaro::Content::Processors::CustomLexers.apply(lexers_config)
      server_highlight("let", "mydsl").should eq(%(<span class="hljs-keyword">let</span>))
    end
    server_highlight("let", "mydsl").should be_nil
  end

  it "warns about each grammar that does not load, naming the file, and keeps the rest" do
    files = {
      "a_bad_xml.xml" => "<lexer><config><name>X</name></config>\n<rules>\n",
      "b_bad_re.xml"  => "<lexer><config><name>Y</name></config><rules><state name=\"root\"><rule pattern=\"(open\"><token type=\"Text\"/></rule></state></rules></lexer>",
      "c_no_name.xml" => %(<lexer><config></config><rules><state name="root"></state></rules></lexer>),
      "d_no_root.xml" => %(<lexer><config><name>Z</name></config><rules><state name="other"></state></rules></lexer>),
      "e_bad_act.xml" => %(<lexer><config><name>W</name></config><rules><state name="root"><rule pattern="x"><bogus/></rule></state></rules></lexer>),
      # A repeated attribute other than Chroma's `state` is malformed.
      "e_dup_attr.xml" => %(<lexer><config><name>S</name></config><rules><state name="root"><rule pattern="a" pattern="b"><token type="Text"/></rule></state></rules></lexer>),
      # States the stock loader only trips over mid-tokenization: loaded,
      # with a warning.
      "f_bad_push.xml" => %(<lexer><config><name>V</name></config><rules><state name="root"><rule pattern="x"><push state="nope"/></rule></state></rules></lexer>),
      "g_bad_incl.xml" => %(<lexer><config><name>U</name></config><rules><state name="root"><rule><include state="missing"/></rule></state></rules></lexer>),
      "h_bad_comb.xml" => %(<lexer><config><name>T</name></config><rules><state name="root"><rule pattern="x"><combined state="root" state="gone"/></rule></state></rules></lexer>),
      "mydsl.xml"      => CUSTOM_GRAMMAR,
      "not-a-grammar"  => "ignored: no .xml extension",
    }
    with_lexers(files) do
      log = with_captured_log { Hwaro::Content::Processors::CustomLexers.apply(lexers_config) }
      log.should contain("lexers/a_bad_xml.xml: not loaded — invalid XML (line 3)")
      log.should contain("lexers/b_bad_re.xml:")
      log.should contain("compiling regex")
      log.should contain("lexers/c_no_name.xml: not loaded — missing <config><name>")
      log.should contain(%(lexers/d_no_root.xml: not loaded — missing <state name="root">))
      log.should contain("lexers/e_bad_act.xml:")
      log.should contain("lexers/e_dup_attr.xml: not loaded — invalid XML (line 1): Attribute pattern redefined")
      log.should contain(%(lexers/f_bad_push.xml: references undefined state "nope" (<push>); code blocks that reach it fall back to plain))
      log.should contain(%(lexers/g_bad_incl.xml: references undefined state "missing" (<include>)))
      log.should contain(%(lexers/h_bad_comb.xml: references undefined state "gone" (<combined>)))
      log.should_not contain("not-a-grammar")
      server_highlight("let", "mydsl").should eq(%(<span class="hljs-keyword">let</span>))
      server_highlight("x", "z").should be_nil

      grammars, problems, _ = Hwaro::Content::Processors::CustomLexers.scan("lexers")
      grammars.map(&.path).should eq(%w[f_bad_push g_bad_incl h_bad_comb mydsl].map { |n| "lexers/#{n}.xml" })
      problems.map(&.[0]).should eq(%w[a_bad_xml b_bad_re c_no_name d_no_root e_bad_act e_dup_attr f_bad_push g_bad_incl h_bad_comb].map { |n| "lexers/#{n}.xml" })
      # A loaded grammar with a dangling state still highlights until it
      # reaches it.
      server_highlight("y", "v").should eq("y")
    end
  end

  # A bundled grammar is the natural starting point, so the loader's own
  # checks (XML, <name>, root state) must accept them all — Chroma's
  # repeated `state` attributes included — and a dangling state reference
  # (psl, sourcepawn, yang) is a warning, not a rejection. The files left
  # out are the ones the stock loader cannot build either (regexes PCRE2
  # refuses, actions Tartrazine lacks).
  it "loads the bundled grammars except the ones the stock loader cannot build" do
    Dir.mktmpdir do |dir|
      Tartrazine::LexerFiles.files.map(&.path).select(&.ends_with?(".xml")).each do |path|
        File.write(File.join(dir, path.lchop('/')), Tartrazine::LexerFiles.get(path).gets_to_end)
      end
      grammars, problems, _ = Hwaro::Content::Processors::CustomLexers.scan(dir)
      grammars.size.should be > 200
      dangling = problems.select { |_, m| m.starts_with?("references undefined state") }.map { |path, _| File.basename(path) }.uniq!
      dangling.sort!.should eq(["psl.xml", "sourcepawn.xml", "yang.xml"])
      dangling.each { |name| grammars.any? { |g| File.basename(g.path) == name }.should be_true }
      problems.each do |_, message|
        next if message.starts_with?("references undefined state") || message.includes?("is already defined by")
        (message.includes?("compiling regex") || message.includes?("Unknown enum Tartrazine::ActionType")).should be_true
      end
    end
  end

  it "keeps the first file (sorted) when two grammars claim a name" do
    second = CUSTOM_GRAMMAR.sub("<name>MyDSL</name>", "<name>Other</name>").sub(%(<rule pattern="\\b(let|emit)\\b">), %(<rule pattern="\\bnever\\b">))
    with_lexers({"a.xml" => CUSTOM_GRAMMAR, "b.xml" => second}) do
      log = with_captured_log { Hwaro::Content::Processors::CustomLexers.apply(lexers_config) }
      log.should contain("lexers/b.xml: 'mydsl' is already defined by lexers/a.xml")
      server_highlight("let", "mydsl").should eq(%(<span class="hljs-keyword">let</span>))
      # The second file still answers to the name nobody else claimed.
      server_highlight("let", "other").should eq("let")
    end
  end

  it "warns about an unreadable grammar instead of aborting the build" do
    with_lexers({"a_locked.xml" => CUSTOM_GRAMMAR.sub("MyDSL", "Locked").sub("<alias>mydsl</alias>", "").sub("<alias>MDSL</alias>", ""), "mydsl.xml" => CUSTOM_GRAMMAR}) do
      File.chmod("lexers/a_locked.xml", 0o000)
      begin
        pending!("a 0o000 file is still readable (root)") if File::Info.readable?("lexers/a_locked.xml")
        log = with_captured_log { Hwaro::Content::Processors::CustomLexers.apply(lexers_config).should_not be_empty }
        log.should contain("lexers/a_locked.xml: not loaded")
        server_highlight("let", "mydsl").should eq(%(<span class="hljs-keyword">let</span>))
      ensure
        File.chmod("lexers/a_locked.xml", 0o644)
      end
    end
  end

  it "lets include_code detect a custom grammar from its <filename> globs" do
    grammar = CUSTOM_GRAMMAR.sub("</config>", "<filename>*.mdsl</filename><filename>Deployfile</filename></config>")
    with_lexers({"mydsl.xml" => grammar}) do
      Hwaro::Content::Processors::CustomLexers.apply(lexers_config)
      Hwaro::Content::Processors::Includes.language_for("ops/site.MDSL").should eq("mydsl")
      Hwaro::Content::Processors::Includes.language_for("Deployfile").should eq("mydsl")
      Hwaro::Content::Processors::Includes.language_for("app.cr").should eq("crystal")
    end
    Hwaro::Content::Processors::Includes.language_for("ops/site.mdsl").should eq("")
  end

  it "warns when the directory is missing" do
    with_lexers({} of String => String) do
      log = with_captured_log { Hwaro::Content::Processors::CustomLexers.apply(lexers_config("nope")).should eq("") }
      log.should contain("[highlight] lexers_dir: nope — directory not found")
    end
  end

  it "ignores the grammars with a warning in client mode" do
    with_lexers({"mydsl.xml" => CUSTOM_GRAMMAR}) do
      log = with_captured_log { Hwaro::Content::Processors::CustomLexers.apply(lexers_config(mode: "client")).should eq("") }
      log.should contain(%(lexers_dir is ignored with mode = "client"))
      Hwaro::Content::Processors::CustomLexers.custom?("mydsl").should be_false
    end
  end

  it "changes the digest when a grammar's bytes change, and is empty without the setting" do
    with_lexers({"mydsl.xml" => CUSTOM_GRAMMAR}) do
      first = Hwaro::Content::Processors::CustomLexers.apply(lexers_config)
      Hwaro::Content::Processors::CustomLexers.apply(lexers_config).should eq(first)
      File.write("lexers/mydsl.xml", CUSTOM_GRAMMAR.sub("let|emit", "emit"))
      Hwaro::Content::Processors::CustomLexers.apply(lexers_config).should_not eq(first)
      Hwaro::Content::Processors::CustomLexers.apply(lexers_config(nil)).should eq("")
      Hwaro::Content::Processors::CustomLexers.digest.should eq("")
    end
  end
end

private LEXERS_SITE_CONFIG = <<-TOML
  title = "t"
  base_url = "https://example.com"
  [highlight]
  lexers_dir = "lexers"
  TOML

private LEXERS_SITE_PAGE = "+++\ntitle = \"P\"\n+++\n\n```mydsl\nlet x\n```\n\n```ruby\nputs 1\n```\n"

private def lexers_rebuild(builder : Hwaro::Core::Build::Builder, cache : Bool) : String
  builder.run(Hwaro::Config::Options::BuildOptions.new(output_dir: "public", parallel: false, cache: cache, highlight: true)).should be_true
  File.read("public/p/index.html")
end

describe "build with [highlight] lexers_dir" do
  it "highlights a custom language at build time, before and after the grammar exists" do
    log = with_captured_log do
      build_site(LEXERS_SITE_CONFIG, content_files: {"p.md" => LEXERS_SITE_PAGE},
        template_files: {"page.html" => "{{ content }}"}, highlight: true) do |_, builder|
        before = File.read("public/p/index.html")
        before.should contain(%(<code class="language-mydsl hljs">let x\n))
        before.should contain(%(<span class="hljs-built_in">puts</span>))

        FileUtils.mkdir_p("lexers")
        File.write("lexers/mydsl.xml", CUSTOM_GRAMMAR)
        after = lexers_rebuild(builder, cache: false)
        after.should contain(%(<code class="language-mydsl hljs"><span class="hljs-keyword">let</span> x))
        after.should contain(%(<span class="hljs-built_in">puts</span>))
      end
    end
    log.should contain("[highlight] lexers_dir: lexers — directory not found")
  ensure
    Hwaro::Content::Processors::CustomLexers.apply(Hwaro::Models::Config.new)
  end

  it "re-renders cached pages when a grammar file changes under --cache" do
    build_site(LEXERS_SITE_CONFIG, content_files: {"p.md" => LEXERS_SITE_PAGE},
      template_files: {"page.html" => "{{ content }}"}, highlight: true, cache: true) do |_, builder|
      FileUtils.mkdir_p("lexers")
      File.write("lexers/mydsl.xml", CUSTOM_GRAMMAR)
      lexers_rebuild(builder, cache: true).should contain(%(<span class="hljs-keyword">let</span> x))

      File.write("lexers/mydsl.xml", CUSTOM_GRAMMAR.sub("let|emit", "emit"))
      lexers_rebuild(builder, cache: true).should contain(%(<code class="language-mydsl hljs">let x))
      # Unchanged grammars keep the warm cache valid.
      lexers_rebuild(builder, cache: true).should contain(%(<code class="language-mydsl hljs">let x))
    end
  ensure
    Hwaro::Content::Processors::CustomLexers.apply(Hwaro::Models::Config.new)
  end

  it "loads nothing for a site without the setting" do
    build_site(%(title = "t"\nbase_url = "https://example.com"\n), content_files: {"p.md" => LEXERS_SITE_PAGE},
      template_files: {"page.html" => "{{ content }}"}, highlight: true) do
      FileUtils.mkdir_p("lexers")
      Hwaro::Content::Processors::CustomLexers.digest.should eq("")
      Hwaro::Content::Processors::SyntaxHighlighter.body_fingerprint.size.should eq(3)
      File.read("public/p/index.html").should contain(%(<code class="language-mydsl hljs">let x\n))
    end
  end
end
