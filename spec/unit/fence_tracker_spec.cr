require "../spec_helper"

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

    it "does not open on 4-space-indented delimiters" do
      feed(["    ```", "text"]).should eq [false, false]
    end

    it "keeps a blockquoted delimiter literal inside an open top-level fence" do
      feed(["```", "> ```", "still code", "```"]).should eq [true, true, true, true]
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

    it "does not open on indented code inside a blockquote" do
      feed(["> mono:", ">     ```", "> text"]).should eq [false, false, false]
    end
  end
end
