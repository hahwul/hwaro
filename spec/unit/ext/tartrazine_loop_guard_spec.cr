require "../../spec_helper"
require "../../../src/content/processors/syntax_highlighter"

# ext/tartrazine_loop_guard.cr — grammars that would tokenize forever (a
# zero-width match that makes no progress) or recurse until the stack
# overflows (`<usingself>` / `<using>` of itself) degrade to plain output.

private def guard_grammar(name : String, rule : String) : String
  %(<lexer><config><name>#{name}</name></config><rules><state name="root">#{rule}</state></rules></lexer>)
end

private def with_guard_grammar(xml : String, &)
  names, filenames, template, _, _ = Tartrazine.hwaro_parse_custom_lexer(xml)
  Tartrazine.hwaro_register_custom_lexers([{names, filenames, template}])
  Hwaro::Content::Processors::ServerHighlighter.reset_memos
  yield
ensure
  Tartrazine.hwaro_register_custom_lexers([] of {Array(String), Array(String), Tartrazine::LexerTemplate})
  Hwaro::Content::Processors::ServerHighlighter.reset_memos
end

# Highlights on its own thread so a regression that spins forever fails
# this example after `limit` instead of hanging the suite.
private def highlight_within(code : String, lang : String, limit : Time::Span = 10.seconds) : {Bool, String?}
  done = Channel(String?).new(1)
  Fiber::ExecutionContext::Isolated.new("tartrazine-loop-guard-spec") do
    done.send(Hwaro::Content::Processors::ServerHighlighter.highlight(code, lang))
  end
  select
  when result = done.receive
    {true, result}
  when timeout(limit)
    {false, nil}
  end
end

describe "Tartrazine loop guards (ext/tartrazine_loop_guard)" do
  it "gives up on a rule that matches the empty string without progress" do
    with_guard_grammar(guard_grammar("zerowidth", %(<rule pattern="[a-z]*"><token type="Keyword"/></rule>))) do
      log = with_captured_log do
        finished, html = highlight_within("123 abc", "zerowidth")
        finished.should be_true
        html.should be_nil
      end
      log.should contain("Server highlight failed for 'zerowidth'")
      log.should contain("matches the empty string")
    end
  end

  it "still allows zero-width matches that change state" do
    xml = <<-'XML'
      <lexer><config><name>lookahead</name></config><rules>
      <state name="root">
        <rule pattern="(?=\d)"><push state="num"/></rule>
        <rule pattern="[a-z]+"><token type="Keyword"/></rule>
        <rule pattern="\s+"><token type="Text"/></rule>
      </state>
      <state name="num">
        <rule pattern="\d+"><token type="LiteralNumber"/><pop depth="1"/></rule>
      </state>
      </rules></lexer>
      XML
    with_guard_grammar(xml) do
      finished, html = highlight_within("ab 12", "lookahead")
      finished.should be_true
      html.should eq(%(<span class="hljs-keyword">ab</span> <span class="hljs-number">12</span>))
    end
  end

  it "stops <usingself> recursion with a warning instead of overflowing the stack" do
    with_guard_grammar(guard_grammar("selfish", %(<rule pattern=".+"><usingself state="root"/></rule>))) do
      log = with_captured_log do
        finished, html = highlight_within("abc", "selfish")
        finished.should be_true
        html.should be_nil
      end
      log.should contain("nested deeper than 32 levels")
    end
  end

  it "stops <using> of the lexer's own name the same way" do
    with_guard_grammar(guard_grammar("ouroboros", %(<rule pattern=".+"><using lexer="ouroboros"/></rule>))) do
      log = with_captured_log do
        finished, html = highlight_within("abc", "ouroboros")
        finished.should be_true
        html.should be_nil
      end
      log.should contain("nested deeper than 32 levels")
    end
  end

  it "stops an <include> cycle with a warning instead of overflowing the stack" do
    {
      "selfinc" => %(<state name="root"><rule><include state="root"/></rule></state>),
      "twoinc"  => %(<state name="root"><rule pattern="a"><token type="Text"/></rule><rule><include state="b"/></rule></state><state name="b"><rule><include state="root"/></rule></state>),
      "combinc" => %(<state name="root"><rule pattern="x"><token type="Keyword"/><combined state="x" state="y"/></rule></state><state name="x"><rule><include state="x"/></rule></state><state name="y"><rule pattern="q"><token type="Text"/></rule></state>),
    }.each do |name, states|
      with_guard_grammar(%(<lexer><config><name>#{name}</name></config><rules>#{states}</rules></lexer>)) do
        log = with_captured_log do
          finished, html = highlight_within("ab\nxq", name)
          finished.should be_true
          html.should be_nil
        end
        log.should contain("<include> nested deeper than 64 levels")
      end
    end
  end

  # The bundled batchfile grammar recurses through <usingself> until the
  # stack overflows (a ```batchfile fence crashed the whole build on
  # 0.21.0); the depth guard turns that into plain output.
  it "falls back to plain for a bundled batchfile fence instead of crashing" do
    finished, html = highlight_within("echo hi\n", "batchfile")
    finished.should be_true
    html.should be_nil
  end

  it "leaves ordinary nested delegation alone" do
    finished, html = highlight_within(%(<style>a { color: red }</style>), "html")
    finished.should be_true
    html.to_s.should contain("hljs-")
  end
end
