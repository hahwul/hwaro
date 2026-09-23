require "../../../spec_helper"

private def feed(lines : Array(String)) : Array(Bool)
  tracker = Hwaro::Content::Processors::FenceTracker.new
  lines.map { |line| tracker.fence_line?(line) }
end

describe Hwaro::Content::Processors::FenceTracker do
  describe "top-level fences" do
    it "tracks opener, content, and closer" do
      feed(["```", "code", "```", "after"]).should eq [true, true, true, false]
    end

    it "requires a closer at least as long as the opener" do
      feed(["````", "```", "inner", "````", "after"]).should eq [true, true, true, true, false]
    end

    it "treats a backtick in a backtick fence's info string as inline code" do
      feed(["``` `not a fence`", "text"]).should eq [false, false]
    end

    it "treats a 4-space-indented delimiter as indented code, not a fence" do
      # Verbatim as indented-code content — but no fence opens, so the
      # following flush-left line is ordinary markdown again.
      feed(["    ```", "text"]).should eq [true, false]
    end

    it "keeps a blockquoted delimiter literal inside an open top-level fence" do
      feed(["```", "> ```", "still code", "```"]).should eq [true, true, true, true]
    end
  end

  describe "raw HTML code blocks" do
    it "tracks content until a raw-code element closes" do
      feed(["<pre>", "$x$", "</pre>", "~~outside~~"]).should eq [true, true, true, false]
    end

    it "ends the block at any raw-code closing tag, as CommonMark type-1 blocks do" do
      feed(["<pre>", "$x$", "</script>", "~~outside~~"]).should eq [true, true, true, false]
      feed(["<textarea>", "text", "</style>", "~~outside~~"]).should eq [true, true, true, false]
    end

    it "does not open on custom elements whose name starts with a raw-code tag" do
      %w[<style-guide> <pre-view> <script-x> <textarea-foo> <prefix>].each do |tag|
        feed([tag, "~~x~~", "</#{tag[1..]}"]).should eq [false, false, false]
      end
    end

    it "opens on a raw-code tag followed by attributes or the line end" do
      feed(["<pre class=\"x\">", "~~x~~", "</pre>"]).should eq [true, true, true]
      feed(["<script", "~~x~~", "</script>"]).should eq [true, true, true]
    end

    it "tracks raw-code blocks inside blockquotes" do
      feed(["> <pre>", "> $x$", "> </pre>", "> ~~outside raw block~~"])
        .should eq [true, true, true, false]
    end
  end

  describe "blockquoted fences" do
    it "opens and closes a fence behind a single marker" do
      feed(["> ```", "> code", "> ```", "> after"]).should eq [true, true, true, false]
    end

    it "opens and closes a fence behind nested markers" do
      feed(["> > ```", "> > code", "> > ```", "> > after"]).should eq [true, true, true, false]
    end

    it "keeps a deeper-quoted delimiter literal inside a quoted fence" do
      feed(["> ```", "> > ```", "> ```", "> after"]).should eq [true, true, true, false]
    end

    it "treats marker-only blank lines as fence content" do
      feed(["> ```", ">", "> code", "> ```"]).should eq [true, true, true, true]
    end

    it "force-closes when the marker disappears" do
      # CommonMark: fenced code gets no lazy continuation, so the quote —
      # and the fence — end at the unmarked line.
      feed(["> ```", "outside", "~~x~~"]).should eq [true, false, false]
    end

    it "re-evaluates the force-closing line as a new opener" do
      feed(["> ```", "```", "code", "```"]).should eq [true, true, true, true]
    end

    it "allows up to 3 leading spaces before a marker" do
      feed(["   > ```", "   > code", "   > ```"]).should eq [true, true, true]
    end

    it "does not open a fence on indented code inside a blockquote" do
      feed(["> mono:", ">     ```", "> text"]).should eq [false, false, false]
    end
  end

  describe "indented code runs" do
    it "opens after a blank line and survives interior blanks" do
      feed(["para", "", "    code", "", "\tmore", "back"])
        .should eq [false, false, true, true, true, false]
    end

    it "opens at the start of the document" do
      feed(["    code", "text"]).should eq [true, false]
    end

    it "does not open without a preceding blank line" do
      # Indented code cannot interrupt a paragraph (lazy continuation).
      feed(["para", "    still para"]).should eq [false, false]
    end

    it "opens directly after an ATX heading" do
      # CommonMark only forbids indented code from interrupting a
      # *paragraph*; a heading is a leaf block, so Markd opens `<pre><code>`
      # here with no blank line in between. Reporting the line as ordinary
      # text let the walkers transform content Markd renders verbatim.
      feed(["## Example", "    code", "", "back"])
        .should eq [false, true, true, false]
    end

    # Controls (they hold against the pre-fix tracker too): the new
    # heading-arms-indented-code rule must not widen beyond the one line it is
    # about, or ordinary indented prose starts being treated as code.
    it "only arms the line immediately after the heading" do
      feed(["## Example", "text", "    still para"]).should eq [false, false, false]
    end

    it "does not treat a bare `#hashtag` as a heading" do
      feed(["#hashtag", "    still para"]).should eq [false, false]
    end

    it "does not open inside an open list" do
      feed(["- item", "", "    continuation"]).should eq [false, false, false]
    end

    it "opens again once a flush-left block has closed the list" do
      feed(["- item", "", "para", "", "    code"])
        .should eq [false, false, false, false, true]
    end

    it "keeps the list open across indented continuations" do
      feed(["- item", "", "  wrapped", "", "    still list"])
        .should eq [false, false, false, false, false]
    end
  end

  describe "list-indented code" do
    it "tracks code indented four columns beyond a list item's content indent" do
      feed(["- item", "", "      - [ ] code", "      ~~still code~~", "", "- next"])
        .should eq [false, false, true, true, true, false]
    end

    it "tracks nested items indented four or more columns" do
      feed([
        "- a", "", "    - b", "", "        - c", "", "        - d",
        "", "      paragraph of b", "", "          code in b",
      ]).should eq [false, false, false, false, false, false, false, false, false, false, true]
    end

    it "expands tabs to four-column stops for nested items" do
      feed(["- a", "", "\t- b", "", "\t  text of b", "", "\t      code in b"])
        .should eq [false, false, false, false, false, false, true]
    end

    it "keeps deep two-space nesting out of indented code" do
      feed(["- a", "  - b", "    - c", "      - d", "", "        text of d"])
        .should eq [false, false, false, false, false, false]
    end

    it "ends an indented code run where the item's content resumes" do
      feed(["- a", "", "      code", "    text"]).should eq [false, false, true, false]
    end

    it "keeps list items behind a blockquote inside an outer item" do
      feed(["- a", "", "  > quote", "", "  b", "", "     not code"])
        .should eq [false, false, false, false, false, false, false]
    end
  end
end
