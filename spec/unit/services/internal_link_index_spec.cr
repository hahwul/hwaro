require "../../spec_helper"

describe Hwaro::Services::InternalLinkIndex do
  describe ".key" do
    it "splits like InternalLinkResolver: path before '#', then before '?'" do
      Hwaro::Services::InternalLinkIndex.key("@/posts/a.md").should eq("posts/a.md")
      Hwaro::Services::InternalLinkIndex.key("@/posts/a.md#top").should eq("posts/a.md")
      Hwaro::Services::InternalLinkIndex.key("@/posts/a.md?x=1#top").should eq("posts/a.md")
      Hwaro::Services::InternalLinkIndex.key("@/").should eq("")
    end

    it "never decodes or normalizes the path" do
      Hwaro::Services::InternalLinkIndex.key("@/my%20post.md").should eq("my%20post.md")
      Hwaro::Services::InternalLinkIndex.key("@/./x.md").should eq("./x.md")
    end

    it "is nil for anything that is not an @/ link" do
      Hwaro::Services::InternalLinkIndex.key("/posts/a/").should be_nil
      Hwaro::Services::InternalLinkIndex.key("posts/a.md").should be_nil
    end
  end

  describe "#unresolved_reason" do
    it "resolves published pages and sections by their exact content path" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "posts", "bundle"))
        File.write(File.join(dir, "_index.md"), "+++\ntitle = \"Home\"\n+++\n")
        File.write(File.join(dir, "posts", "_index.md"), "+++\ntitle = \"Posts\"\n+++\n")
        File.write(File.join(dir, "posts", "a.MD"), "+++\ntitle = \"A\"\n+++\n")
        File.write(File.join(dir, "posts", "bundle", "index.md"), "+++\ntitle = \"B\"\n+++\n")

        index = Hwaro::Services::InternalLinkIndex.new(dir + "/")
        {"_index.md", "posts/_index.md", "posts/a.MD", "posts/bundle/index.md"}.each do |key|
          index.unresolved_reason(key).should be_nil
        end
        index.unresolved_reason("posts/a.md").should eq("not found")
        index.unresolved_reason("posts/bundle/").should eq("not found")
        index.unresolved_reason("").should eq("empty link")
      end
    end

    it "names the publish state of a target a default build drops" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "drafts"))
        File.write(File.join(dir, "drafts", "_index.md"), "+++\ntitle = \"D\"\n[cascade]\ndraft = true\n+++\n")
        File.write(File.join(dir, "drafts", "child.md"), "+++\ntitle = \"C\"\n+++\n")
        File.write(File.join(dir, "future.md"), "+++\ntitle = \"F\"\ndate = 2999-01-01\n+++\n")

        index = Hwaro::Services::InternalLinkIndex.new(dir)
        index.unresolved_reason("drafts/child.md").should eq("draft")
        index.unresolved_reason("future.md").should eq("future")
        Hwaro::Services::InternalLinkIndex.describe("future").should eq("target is future-dated")
      end
    end
  end
end
