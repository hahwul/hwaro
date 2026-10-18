require "../../spec_helper"

# ext/tartrazine_lexer_alias_fix.cr — `cr` and `yml` fences highlight like
# `crystal` and `yaml` (both are documented fence identifiers).
describe "Tartrazine lexer aliases (ext/tartrazine_lexer_alias_fix)" do
  it "highlights cr and yml fences in server mode" do
    {"cr" => {"puts 1", "crystal"}, "yml" => {"a: 1 # c", "yaml"}}.each do |short, (code, long)|
      html = Hwaro::Content::Processors::ServerHighlighter.highlight(code, short)
      html.to_s.should contain("hljs-")
      html.should eq(Hwaro::Content::Processors::ServerHighlighter.highlight(code, long))
    end
  end
end
