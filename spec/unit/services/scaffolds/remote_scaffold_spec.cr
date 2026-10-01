require "../../../spec_helper"
require "../../../../src/services/scaffolds/remote"

describe Hwaro::Services::Scaffolds::Remote do
  describe ".remote?" do
    it "detects github: shorthand" do
      Hwaro::Services::Scaffolds::Remote.remote?("github:hahwul/hwaro-starter-blog").should be_true
    end

    it "detects https:// URL" do
      Hwaro::Services::Scaffolds::Remote.remote?("https://github.com/hahwul/hwaro-starter-blog").should be_true
    end

    it "detects http:// URL" do
      Hwaro::Services::Scaffolds::Remote.remote?("http://github.com/hahwul/hwaro-starter-blog").should be_true
    end

    it "detects git: shorthand" do
      Hwaro::Services::Scaffolds::Remote.remote?("git:owasp-noir/noir/docs").should be_true
    end

    it "returns false for built-in scaffold names" do
      Hwaro::Services::Scaffolds::Remote.remote?("simple").should be_false
      Hwaro::Services::Scaffolds::Remote.remote?("blog").should be_false
      Hwaro::Services::Scaffolds::Remote.remote?("docs").should be_false
    end
  end

  describe ".parse_source" do
    it "parses github:owner/repo shorthand" do
      owner, repo, subpath = Hwaro::Services::Scaffolds::Remote.parse_source("github:hahwul/hwaro-starter-blog")
      owner.should eq("hahwul")
      repo.should eq("hwaro-starter-blog")
      subpath.should eq("")
    end

    it "parses github:owner/repo/subpath shorthand" do
      owner, repo, subpath = Hwaro::Services::Scaffolds::Remote.parse_source("github:hahwul/hwaro/docs")
      owner.should eq("hahwul")
      repo.should eq("hwaro")
      subpath.should eq("docs")
    end

    it "parses github:owner/repo/deep/subpath shorthand" do
      owner, repo, subpath = Hwaro::Services::Scaffolds::Remote.parse_source("github:hahwul/hwaro/themes/starter")
      owner.should eq("hahwul")
      repo.should eq("hwaro")
      subpath.should eq("themes/starter")
    end

    it "parses git: shorthand" do
      owner, repo, subpath = Hwaro::Services::Scaffolds::Remote.parse_source("git:owasp-noir/noir/docs")
      owner.should eq("owasp-noir")
      repo.should eq("noir")
      subpath.should eq("docs")
    end

    it "routes git://github.com/owner/repo through the URL parser (not git: shorthand)" do
      owner, repo, subpath = Hwaro::Services::Scaffolds::Remote.parse_source("git://github.com/hahwul/hwaro-starter-blog")
      owner.should eq("hahwul")
      repo.should eq("hwaro-starter-blog")
      subpath.should eq("")
    end

    it "parses git://github.com/owner/repo/subpath via the URL parser" do
      owner, repo, subpath = Hwaro::Services::Scaffolds::Remote.parse_source("git://github.com/owner/repo/docs")
      owner.should eq("owner")
      repo.should eq("repo")
      subpath.should eq("docs")
    end

    it "parses https://github.com/owner/repo URL" do
      owner, repo, subpath = Hwaro::Services::Scaffolds::Remote.parse_source("https://github.com/hahwul/hwaro-starter-blog")
      owner.should eq("hahwul")
      repo.should eq("hwaro-starter-blog")
      subpath.should eq("")
    end

    it "parses GitHub URL with /tree/branch/subpath" do
      owner, repo, subpath = Hwaro::Services::Scaffolds::Remote.parse_source("https://github.com/hahwul/hwaro/tree/main/docs")
      owner.should eq("hahwul")
      repo.should eq("hwaro")
      subpath.should eq("docs")
    end

    it "parses GitHub URL with deep subpath" do
      owner, repo, subpath = Hwaro::Services::Scaffolds::Remote.parse_source("https://github.com/hahwul/hwaro/tree/main/themes/starter")
      owner.should eq("hahwul")
      repo.should eq("hwaro")
      subpath.should eq("themes/starter")
    end

    it "parses GitHub URL with direct subpath (no /tree/branch/)" do
      owner, repo, subpath = Hwaro::Services::Scaffolds::Remote.parse_source("https://github.com/owasp-noir/noir/docs")
      owner.should eq("owasp-noir")
      repo.should eq("noir")
      subpath.should eq("docs")
    end

    it "strips .git suffix from URL" do
      owner, repo, subpath = Hwaro::Services::Scaffolds::Remote.parse_source("https://github.com/hahwul/hwaro-starter-blog.git")
      owner.should eq("hahwul")
      repo.should eq("hwaro-starter-blog")
      subpath.should eq("")
    end

    it "handles URL with trailing slash" do
      owner, repo, subpath = Hwaro::Services::Scaffolds::Remote.parse_source("https://github.com/hahwul/hwaro-starter-blog/")
      owner.should eq("hahwul")
      repo.should eq("hwaro-starter-blog")
      subpath.should eq("")
    end

    it "raises on invalid github shorthand" do
      expect_raises(ArgumentError) do
        Hwaro::Services::Scaffolds::Remote.parse_source("github:invalid")
      end
    end

    it "raises on non-github URL" do
      expect_raises(ArgumentError) do
        Hwaro::Services::Scaffolds::Remote.parse_source("https://gitlab.com/user/repo")
      end
    end

    it "raises on github URL without repo" do
      expect_raises(ArgumentError) do
        Hwaro::Services::Scaffolds::Remote.parse_source("https://github.com/hahwul")
      end
    end
  end

  describe "#extract_front_matter (via content_files)" do
    # Test the extract_front_matter logic directly via a helper instance
    it "extracts TOML front matter (+++ delimiters)" do
      input = "+++\ntitle = \"Hello\"\nweight = 1\n+++\n\nThis is body content.\n\n## Heading\n\nMore text."
      expected = "+++\ntitle = \"Hello\"\nweight = 1\n+++\n"

      # Use a test subclass to expose the private method
      result = TestRemoteHelper.extract(input)
      result.should eq(expected)
    end

    it "extracts YAML front matter (--- delimiters)" do
      input = "---\ntitle: Hello\nweight: 1\n---\n\nBody content here."
      expected = "---\ntitle: Hello\nweight: 1\n---\n"

      result = TestRemoteHelper.extract(input)
      result.should eq(expected)
    end

    it "returns original content if no front matter" do
      input = "# Just a heading\n\nSome text."
      result = TestRemoteHelper.extract(input)
      result.should eq(input)
    end

    it "returns original content if front matter is not closed" do
      input = "+++\ntitle = \"Unclosed\"\nno closing delimiter"
      result = TestRemoteHelper.extract(input)
      result.should eq(input)
    end

    it "handles empty front matter" do
      input = "+++\n+++\n\nBody."
      expected = "+++\n+++\n"

      result = TestRemoteHelper.extract(input)
      result.should eq(expected)
    end
  end
end

# Helper to test the private extract_front_matter method
class TestRemoteHelper < Hwaro::Services::Scaffolds::Remote
  # Canned HTTP response that subclasses can swap in instead of calling GitHub.
  @@stub_status : Int32 = 200
  @@stub_body : String = ""

  def self.stub_response(status : Int32, body : String = "")
    @@stub_status = status
    @@stub_body = body
  end

  def initialize
    @config_data = ""
    @content_data = {} of String => String
    @template_data = {} of String => String
    @static_data = {} of String => String
    @shortcode_data = {} of String => String
    @description_text = "test"
  end

  def self.extract(content : String) : String
    instance = new
    instance.do_extract(content)
  end

  def do_extract(content : String) : String
    extract_front_matter(content)
  end

  # Invoke the private fetch_default_branch with the stubbed response so we
  # can assert the classification behavior without talking to github.com.
  def do_fetch_default_branch(owner : String, repo : String) : String
    fetch_default_branch(owner, repo)
  end

  # Override the private HTTP hop so the classifier path can be exercised
  # deterministically.
  private def github_api_get(path : String) : HTTP::Client::Response
    HTTP::Client::Response.new(@@stub_status, @@stub_body)
  end
end

describe Hwaro::Services::Scaffolds::Remote do
  describe "#fetch_default_branch error classification" do
    it "raises HwaroError(HWARO_E_NETWORK) with exit 7 on HTTP 404" do
      TestRemoteHelper.stub_response(404, %({"message":"Not Found"}))
      helper = TestRemoteHelper.new

      err = expect_raises(Hwaro::HwaroError) do
        helper.do_fetch_default_branch("this-does-not-exist", "nope")
      end

      err.code.should eq(Hwaro::Errors::HWARO_E_NETWORK)
      err.category.should eq(:network)
      err.exit_code.should eq(7)
      err.message.not_nil!.should contain("this-does-not-exist/nope")
    end

    it "raises HwaroError(HWARO_E_NETWORK) with exit 7 on HTTP 403 rate limit" do
      TestRemoteHelper.stub_response(403, %({"message":"API rate limit exceeded"}))
      helper = TestRemoteHelper.new

      err = expect_raises(Hwaro::HwaroError) do
        helper.do_fetch_default_branch("some-owner", "some-repo")
      end

      err.code.should eq(Hwaro::Errors::HWARO_E_NETWORK)
      err.exit_code.should eq(7)
      err.message.not_nil!.should contain("rate limit")
    end

    it "raises HwaroError(HWARO_E_NETWORK) with exit 7 on generic HTTP failure" do
      TestRemoteHelper.stub_response(500, %({"message":"Internal Server Error"}))
      helper = TestRemoteHelper.new

      err = expect_raises(Hwaro::HwaroError) do
        helper.do_fetch_default_branch("some-owner", "some-repo")
      end

      err.code.should eq(Hwaro::Errors::HWARO_E_NETWORK)
      err.exit_code.should eq(7)
      err.message.not_nil!.should contain("HTTP 500")
    end

    it "raises HwaroError(HWARO_E_NETWORK) when a 200 body is missing 'default_branch'" do
      TestRemoteHelper.stub_response(200, %({"name":"repo"}))
      helper = TestRemoteHelper.new

      err = expect_raises(Hwaro::HwaroError) do
        helper.do_fetch_default_branch("some-owner", "some-repo")
      end

      err.code.should eq(Hwaro::Errors::HWARO_E_NETWORK)
      err.exit_code.should eq(7)
      err.message.not_nil!.should contain("missing 'default_branch'")
    end

    # A non-JSON 200 body crashes in JSON.parse BEFORE the `|| raise`, so it
    # surfaces as a bare JSON::ParseException (not a classified HwaroError).
    # This pins the current unguarded behavior.
    it "raises JSON::ParseException on a non-JSON 200 body (unguarded)" do
      TestRemoteHelper.stub_response(200, "<html>not json</html>")
      helper = TestRemoteHelper.new

      expect_raises(JSON::ParseException) do
        helper.do_fetch_default_branch("some-owner", "some-repo")
      end
    end
  end
end

describe Hwaro::Services::Scaffolds::Remote do
  describe ".parse" do
    it "keeps the branch a /tree/<branch>/ URL names" do
      source = Hwaro::Services::Scaffolds::Remote.parse("https://github.com/o/r/tree/dev/site")
      source.branch.should eq("dev")
      source.subpath.should eq("site")
    end

    it "leaves the branch nil when the URL names none" do
      Hwaro::Services::Scaffolds::Remote.parse("https://github.com/o/r/site").branch.should be_nil
      Hwaro::Services::Scaffolds::Remote.parse("github:o/r/site").branch.should be_nil
    end

    it "drops empty segments from a shorthand subpath (trailing / doubled slash)" do
      Hwaro::Services::Scaffolds::Remote.parse("github:o/r/docs/").subpath.should eq("docs")
      Hwaro::Services::Scaffolds::Remote.parse("github:o/r/a//b").subpath.should eq("a/b")
    end

    it "strips .git from a shorthand repository name" do
      Hwaro::Services::Scaffolds::Remote.parse("github:o/r.git").repo.should eq("r")
    end

    it "accepts a mixed-case GitHub host" do
      Hwaro::Services::Scaffolds::Remote.parse("https://GitHub.com/o/r").repo.should eq("r")
    end

    it "decodes percent-encoded URL segments" do
      Hwaro::Services::Scaffolds::Remote.parse("https://github.com/o/r/tree/main/my%20site").subpath.should eq("my site")
    end
  end

  describe ".ref_candidates" do
    it "tries every branch/subpath split, shortest branch first" do
      Hwaro::Services::Scaffolds::Remote.ref_candidates("feature", "x/docs").should eq([
        {"feature", "x/docs"},
        {"feature/x", "docs"},
        {"feature/x/docs", ""},
      ])
    end
  end

  describe ".classify" do
    it "collects data/, i18n/ and archetypes/ alongside the built-in categories" do
      remote = Hwaro::Services::Scaffolds::Remote
      remote.classify("data/sidebar.yml").should eq({:extra, "data/sidebar.yml"})
      remote.classify("i18n/ko.toml").should eq({:extra, "i18n/ko.toml"})
      remote.classify("archetypes/posts.md").should eq({:archetype, "posts.md"})
      remote.classify("config.toml").should eq({:config, ""})
    end

    it "accepts every content extension the build reads" do
      Hwaro::Services::Scaffolds::Remote.classify("content/post.markdown").should eq({:content, "post.markdown"})
      Hwaro::Services::Scaffolds::Remote.classify("content/image.png").should be_nil
    end

    it "skips unrelated files and keeps traversal inside its directory" do
      Hwaro::Services::Scaffolds::Remote.classify("README.md").should be_nil
      Hwaro::Services::Scaffolds::Remote.classify("data/../../etc/passwd").should eq({:extra, "data/etc/passwd"})
    end
  end

  describe ".dangerous_settings" do
    it "flags the [build.hooks] table form the loader reads" do
      config = "[build.hooks]\npre = [\"curl evil | sh\"]\n"
      Hwaro::Services::Scaffolds::Remote.dangerous_settings(config).should eq(["build hooks (hooks.pre / hooks.post)"])
    end

    it "flags inline-table hooks and deployment target commands" do
      config = "[build]\nhooks = { post = [\"x\"] }\n\n[[deployment.targets]]\nname = \"a\"\ncommand = \"rm -rf /\"\n"
      Hwaro::Services::Scaffolds::Remote.dangerous_settings(config).size.should eq(2)
    end

    it "does not flag a harmless config" do
      Hwaro::Services::Scaffolds::Remote.dangerous_settings("title = \"Hooks and commands\"\n").should be_empty
    end
  end
end

# Drives `fetch!` with canned tree/file responses instead of GitHub.
class FetchStubRemote < Hwaro::Services::Scaffolds::Remote
  @@failing = Set(String).new
  @@calls = [] of String

  def self.failing=(paths : Set(String))
    @@failing = paths
  end

  def self.calls
    @@calls
  end

  def initialize(source : String)
    @config_data = ""
    @content_data = {} of String => String
    @template_data = {} of String => String
    @static_data = {} of String => String
    @shortcode_data = {} of String => String
    @description_text = "stub"
    fetch!(self.class.parse(source))
  end

  private def fetch_default_branch(owner : String, repo : String) : String
    "main"
  end

  private def fetch_tree(owner : String, repo : String, branch : String, missing_ok : Bool = false) : Array(JSON::Any)?
    @@calls << "tree:#{branch}"
    return if missing_ok && branch != "feature/x"
    paths = ["config.toml", "templates/page.html", "data/menu.yml", "docs/config.toml"]
    JSON.parse(paths.map { |p| {path: p, type: "blob"} }.to_json).as_a
  end

  private def fetch_file(owner : String, repo : String, branch : String, path : String) : String
    @@calls << "file:#{branch}:#{path}"
    raise "HTTP 503" if @@failing.includes?(path)
    "body of #{path}"
  end
end

describe "Remote scaffold fetching" do
  it "fails the scaffold instead of writing empty files when a download fails" do
    FetchStubRemote.failing = Set{"templates/page.html"}
    err = expect_raises(Hwaro::HwaroError) do
      with_captured_log { FetchStubRemote.new("github:o/r") }
    end
    err.code.should eq(Hwaro::Errors::HWARO_E_NETWORK)
    (err.message || "").should contain("templates/page.html")
  ensure
    FetchStubRemote.failing = Set(String).new
  end

  it "carries data/ over as a root-relative extra file" do
    remote : FetchStubRemote? = nil
    with_captured_log { remote = FetchStubRemote.new("github:o/r") }
    remote = remote.not_nil!
    remote.extra_files.should eq({"data/menu.yml" => "body of data/menu.yml"})
    remote.config_content.should eq("body of config.toml")
  end

  it "resolves a slash-containing branch from a /tree/ URL and fetches from it" do
    FetchStubRemote.calls.clear
    with_captured_log { FetchStubRemote.new("https://github.com/o/r/tree/feature/x/docs") }
    FetchStubRemote.calls.should contain("tree:feature")
    FetchStubRemote.calls.should contain("file:feature/x:docs/config.toml")
  end
end

# Every tree probe 404s, as GitHub answers for a private/missing repository.
class MissingRepoRemote < FetchStubRemote
  # Typed as possibly-present (never at runtime): a body that can only be
  # nil makes the rest of `fetch!` unreachable, and Crystal 1.21's codegen
  # then crashes on the download-pool closure ("GEP into unsized type").
  private def fetch_tree(owner : String, repo : String, branch : String, missing_ok : Bool = false) : Array(JSON::Any)?
    branch.empty? ? [] of JSON::Any : nil
  end

  private def fetch_default_branch(owner : String, repo : String) : String
    raise Hwaro::HwaroError.new(code: Hwaro::Errors::HWARO_E_NETWORK, message: "Remote scaffold not found: #{owner}/#{repo}")
  end
end

describe "Remote scaffold branch resolution" do
  it "reports a missing/private repository rather than a missing branch" do
    expect_raises(Hwaro::HwaroError, /Remote scaffold not found/) do
      with_captured_log { MissingRepoRemote.new("https://github.com/o/private/tree/main/site") }
    end
  end
end
