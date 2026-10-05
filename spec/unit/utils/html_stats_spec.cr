require "../../spec_helper"

private def stats_of(html : String) : Hwaro::Utils::HtmlStats
  stats = Hwaro::Utils::HtmlStats.new
  stats.add(html)
  stats
end

describe Hwaro::Utils::HtmlStats do
  describe ".scan (via #add)" do
    it "collects lowercased tags, split classes and ids" do
      stats = stats_of(%(<!DOCTYPE html><HTML lang=en><body class="a  b\tc" id=main><DIV Class='X y'>t</DIV><svg:rect id="r"/><br/>))
      stats.tags.to_a.sort.should eq(["body", "br", "div", "html", "svg:rect"])
      stats.classes.to_a.sort.should eq(["X", "a", "b", "c", "y"])
      stats.ids.to_a.sort.should eq(["main", "r"])
    end

    it "skips comments, end tags and script/style bodies" do
      stats = stats_of(%(<!-- <i class="c1"> --><script>if(a<b){x("<p class=z>")}</script><style>a<b{}</style><em class="ok"></em>))
      stats.tags.to_a.sort.should eq(["em", "script", "style"])
      stats.classes.to_a.should eq(["ok"])
    end

    it "ends raw-text elements at a closer in any case" do
      stats = stats_of(%(<Script>x("<i class=no>")</SCRIPT ><p class="yes"><STYLE>a<b{}</Style><em class="also">))
      stats.classes.to_a.sort.should eq(["also", "yes"])
      stats.tags.to_a.sort.should eq(["em", "p", "script", "style"])
    end

    it "decodes entities in values and drops empty ids" do
      stats = stats_of(%(<p class="q&amp;r [&amp;>*]:p-4" id=""><a id=" x ">))
      stats.classes.to_a.sort.should eq(["[&>*]:p-4", "q&r"])
      stats.ids.to_a.should eq(["x"])
    end

    it "does not loop or raise on truncated markup" do
      ["<", "<a", "<a class", "<a class=", "<a class=\"x", "<!--", "<script>a<b", "<a =x>"].each do |html|
        stats_of(html)
      end
    end
  end

  it "serializes sorted values under htmlElements in a stable key order" do
    stats = stats_of(%(<b class="z a" id="y"><a id="x">))
    stats.serialize.should eq(<<-JSON)
      {
        "htmlElements": {
          "tags": [
            "a",
            "b"
          ],
          "classes": [
            "a",
            "z"
          ],
          "ids": [
            "x",
            "y"
          ]
        }
      }

      JSON
  end

  it "writes only when the content changed, keeping the mtime otherwise" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "hwaro_stats.json")
      stats = stats_of(%(<p class="a">))
      stats.write(path)
      past = Time.utc - 1.hour
      File.utime(past, past, path)
      stats.write(path)
      (File.info(path).modification_time - past).abs.should be < 1.second

      stats.add(%(<p class="b">))
      stats.write(path)
      File.read(path).should contain(%("b"))
      (File.info(path).modification_time - past).should be > 1.minute
    end
  end

  it "folds in a previous file and ignores a malformed one" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "hwaro_stats.json")
      stats_of(%(<p class="old" id="i">)).write(path)
      stats = stats_of(%(<em class="new">))
      stats.merge_file(path)
      stats.classes.to_a.sort.should eq(["new", "old"])
      stats.tags.to_a.sort.should eq(["em", "p"])

      Hwaro::Utils::HtmlStats.valid_file?(path).should be_true
      File.write(path, %({"htmlElements": 5}))
      Hwaro::Utils::HtmlStats.valid_file?(path).should be_false
      stats_of("<em>").merge_file(path)

      File.write(path, "{not json")
      Hwaro::Utils::HtmlStats.valid_file?(path).should be_false
      fresh = stats_of(%(<em>))
      fresh.merge_file(path)
      fresh.tags.to_a.should eq(["em"])
      fresh.merge_file(File.join(dir, "missing.json"))
    end
  end
end
