require "../../../spec_helper"
require "../../../../src/services/scaffolds/registry"

# Behavior of the JavaScript the blog/docs/book scaffolds ship.
describe "scaffold scripts" do
  node = Process.find_executable("node")

  describe "search highlighting" do
    search_js = Hwaro::Services::Scaffolds::Blog.new.static_files["js/search.js"]

    it "matches on the raw text and escapes pieces afterwards" do
      search_js.should_not contain("escapeHtml(text).replace(re")
      search_js.should contain("lower.indexOf(q, pos)")
    end

    it "keeps entities intact and still highlights queries containing & < >" do
      pending!("node is not installed") unless node

      start = search_js.index!("function escapeHtml")
      finish = search_js.index!("function getSnippet")
      script = <<-JS
        var document = { createElement: function () {
          return { set textContent(v) { this.t = String(v); },
                   get innerHTML() { return this.t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); } };
        } };
        #{search_js[start...finish]}
        console.log(JSON.stringify([
          highlightMatch('Tips & Tricks', 'm'),
          highlightMatch('Q&A', 'a'),
          highlightMatch('a<b', 'lt'),
          highlightMatch('R&D', 'R&D'),
          highlightMatch('Hello', ''),
        ]));
        JS
      output = IO::Memory.new
      status = Process.run(node.not_nil!, ["-e", script], output: output, error: Process::Redirect::Inherit)
      status.success?.should be_true
      JSON.parse(output.to_s).as_a.map(&.as_s).should eq([
        "Tips &amp; Tricks",
        "Q&amp;<mark>A</mark>",
        "a&lt;b",
        "<mark>R&amp;D</mark>",
        "Hello",
      ])
    end
  end

  describe "book.js" do
    book_js = Hwaro::Services::Scaffolds::Book.new.static_files["js/book.js"]

    it "ignores arrow keys pressed with a modifier" do
      guard = book_js.index!("e.altKey || e.ctrlKey || e.metaKey || e.shiftKey")
      guard.should be < book_js.index!("e.key === 'ArrowLeft'")
    end

    it "guards every localStorage access" do
      book_js.scan(/localStorage\.\w+Item/).size.should eq(2)
      book_js.scan(/try \{[^}]*localStorage\.\w+Item[^}]*\} catch/).size.should eq(2)
    end

    it "is syntactically valid JavaScript" do
      pending!("node is not installed") unless node
      status = Process.run(node.not_nil!, ["--input-type=commonjs", "-e", "new Function(process.argv[1])", "--", book_js])
      status.success?.should be_true
    end
  end
end
