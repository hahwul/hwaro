require "../../spec_helper"

private def route_index_config(dir : String, body : String) : Hwaro::Models::Config
  path = File.join(dir, "config.toml")
  File.write(path, "title = \"T\"\nbase_url = \"https://example.com\"\n#{body}")
  Hwaro::Models::Config.load(path)
end

private def route_index_page(content : String, relative : String, front_matter : String)
  path = File.join(content, relative)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, "+++\ntitle = \"T\"\n#{front_matter}\n+++\nBody\n")
end

describe Hwaro::Services::PageRouteIndex do
  # `[git] use_date` dates a dateless page from its first commit during the
  # build. With a date-token permalink the index cannot know that URL, and
  # used to claim the undated fallback URL instead ("published at
  # /posts/hello/" for a page the build writes under /2025/05/hello/).
  describe "[git] use_date" do
    it "leaves a dateless page whose URL needs the git date out of the index" do
      Dir.mktmpdir do |dir|
        config = route_index_config(dir, "[git]\nenabled = true\nuse_date = true\n[permalinks]\nposts = \"/:year/:month/:slug/\"\n")
        content = File.join(dir, "content")
        route_index_page(content, "posts/hello.md", "")
        route_index_page(content, "posts/world.md", "date = 2025-05-01")

        index = Hwaro::Services::PageRouteIndex.new(content, config)

        index.url_for(File.join(content, "posts", "hello.md")).should be_nil
        index.state_for(File.join(content, "posts", "hello.md")).should be_nil
        index.url_for(File.join(content, "posts", "world.md")).should eq("/2025/05/world/")
      end
    end

    it "still indexes a dateless page whose URL does not use the date" do
      Dir.mktmpdir do |dir|
        config = route_index_config(dir, "[git]\nenabled = true\nuse_date = true\n")
        content = File.join(dir, "content")
        route_index_page(content, "posts/hello.md", "")

        index = Hwaro::Services::PageRouteIndex.new(content, config)

        index.url_for(File.join(content, "posts", "hello.md")).should eq("/posts/hello/")
      end
    end
  end
end
