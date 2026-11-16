require "../../spec_helper"
require "../../../src/content/processors/syntax_highlighter"

# Every lexer Tartrazine bundles compiles and tokenizes a line, with the
# src/ext/tartrazine_* patches applied. A lexer that fails falls back to
# plain output for every code block in its language, silently.

module Tartrazine
  def self.hwaro_spec_bundled_lexer(file : String) : BaseLexer
    create_from_template(file)
  end
end

# Bundled lexers that still fail, and why. Remove an entry once it passes;
# "still fails for every deferred lexer" catches a stale one.
private DEFERRED = {
  # Unbounded lookbehind (`(?<=for\s+)`, `(?<!:\s*)`): Chroma's regexp2
  # allows it, PCRE2 does not (10.43+ allows only bounded variable length).
  "fish" => "unbounded lookbehind",
  "scss" => "unbounded lookbehind",
  # Unbounded lookbehind, and the <mutators> action Tartrazine lacks.
  "v"       => "unbounded lookbehind, <mutators>",
  "v_shell" => "unbounded lookbehind, <mutators>",
  # Actions Tartrazine does not implement.
  "fortranfixed"            => "<mutators>",
  "cassandra_cql"           => "<sublexer_name_group>",
  "materialize_sql_dialect" => "<sublexer_name_group>",
  "postgresql_sql_dialect"  => "<sublexer_name_group>",
  "org_mode"                => "<sublexer_name_group>",
  # `<usingself state="text">` is run from `root` (the state is ignored), so
  # the whitespace rule delegates to itself until the loop guard stops it.
  "batchfile" => "<usingself state> ignored",
  # A keyword alternation past PCRE2's 64 KB compiled-pattern cap.
  "openedge_abl" => "regular expression is too large",
  "racket"       => "regular expression is too large",
}

private def bundled_lexer_error(file : String) : String?
  Tartrazine.hwaro_spec_bundled_lexer(file).tokenizer("x = 1\n").to_a
  nil
rescue ex
  ex.message || ex.class.name
end

describe "Tartrazine bundled lexers" do
  files = Tartrazine::LexerFiles.files.map(&.path).select(&.ends_with?(".xml")).map { |path| File.basename(path, ".xml") }.sort!

  it "bundles lexers" do
    files.size.should be > 200
  end

  it "compiles and tokenizes every lexer not deferred" do
    failures = files.reject { |file| DEFERRED.has_key?(file) }.compact_map do |file|
      bundled_lexer_error(file).try { |error| "#{file}: #{error}" }
    end
    failures.should be_empty
  end

  it "still fails for every deferred lexer" do
    DEFERRED.keys.reject { |file| bundled_lexer_error(file) }.should be_empty
  end

  it "highlights the lexers whose patterns needed rewriting" do
    {
      "agda"         => {"id : Set₁ → Set₁", %(<span class="hljs-type">Set₁</span>)},
      "objectpascal" => {"begin WriteLn('é'); end.", %(<span class="hljs-keyword">begin</span>)},
      "wgsl"         => {"fn main() -> u32 { return 0u; }", %(<span class="hljs-keyword">fn</span>)},
      "al"           => {"procedure Add(a: Integer)", %(<span class="hljs-keyword">procedure</span>)},
    }.each do |lang, (code, span)|
      Hwaro::Content::Processors::ServerHighlighter.highlight(code, lang).to_s.should contain(span)
    end
  end
end
