require "../../../spec_helper"
require "../../../../src/services/scaffolds/docs"

# The scaffold search overlay highlights matches in titles and snippets. It
# must match the RAW text and escape each piece, so a query such as `&`,
# `amp` or `lt` never lands inside an HTML entity. Executed under node when
# available (the function is plain ES5); pending otherwise.
private def run_highlight(js : String, text : String, query : String) : String
  fn = js.match(/function highlightMatch\(.*?\n\n/m).try(&.[0]) || raise "highlightMatch not found"
  script = <<-JS
    function escapeHtml(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
    #{fn}
    process.stdout.write(highlightMatch(#{text.to_json}, #{query.to_json}));
    JS
  io = IO::Memory.new
  Process.run("node", ["-e", script], output: io, error: Process::Redirect::Inherit)
  io.to_s
end

describe "scaffold search highlightMatch" do
  node = Process.find_executable("node")
  js = Hwaro::Services::Scaffolds::Docs.new.static_files["js/search.js"]

  it "never splits an HTML entity" do
    pending!("node not installed") unless node
    run_highlight(js, "Q&A time", "&").should eq("Q<mark>&amp;</mark>A time")
    run_highlight(js, "Q&A time", "amp").should eq("Q&amp;A time")
    run_highlight(js, "a < b > c", "lt").should eq("a &lt; b &gt; c")
  end

  it "highlights case-insensitively and escapes every segment" do
    pending!("node not installed") unless node
    run_highlight(js, "<b>Hello</b> hello", "HELLO").should eq("&lt;b&gt;<mark>Hello</mark>&lt;/b&gt; <mark>hello</mark>")
    run_highlight(js, "x", "").should eq("x")
  end
end
