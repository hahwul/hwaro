require "../../../spec_helper"

# `[content] ignore`: content-relative globs whose matches the build (and
# every tool) never sees. The matcher lives on ContentFilesConfig so the
# non-page consumers that already ask `denied?`/`publish?` honour it too.
describe "[content] ignore" do
  describe "loading" do
    it "is empty by default" do
      config = load_config(%(title = "t"\n))
      config.content_files.ignore.should be_empty
      config.content_files.ignored?("README.md").should be_false
    end

    it "reads an array of globs" do
      config = load_config(%([content]\nignore = ["README.md", "_templates/**"]\n))
      config.content_files.ignore.should eq(["README.md", "_templates/**"])
    end

    it "accepts a single string" do
      load_config(%([content]\nignore = "README.md"\n)).content_files.ignore.should eq(["README.md"])
    end

    it "normalizes a leading /, ./ or content/, repeated trailing / and backslashes" do
      config = load_config(%([content]\nignore = ["/README.md", "./drafts/**", "content/notes", "_templates//", 'a\\b.md', "", "/"]\n))
      config.content_files.ignore.should eq(["README.md", "drafts/**", "notes", "_templates/", "a/b.md"])
    end

    it "warns and keeps the default for a value of the wrong type" do
      config = nil
      log = with_captured_log { config = load_config(%([content]\nignore = 3\n)) }
      log.should contain("[content] ignore")
      config.not_nil!.content_files.ignore.should be_empty
    end

    it "warns about each non-string entry and keeps the string ones" do
      config = nil
      log = with_captured_log { config = load_config(%([content]\nignore = ["README.md", 3, true]\n)) }
      log.should contain("[content] ignore entry 3")
      log.should contain("[content] ignore entry true")
      config.not_nil!.content_files.ignore.should eq(["README.md"])
    end

    # The natural first guess puts the key under [content.files], where it
    # used to hide nothing in silence.
    it "warns that [content.files] ignore has no effect" do
      config = nil
      log = with_captured_log { config = load_config(%([content.files]\nignore = ["README.md"]\n)) }
      log.should contain("[content.files] ignore has no effect")
      config.not_nil!.content_files.ignore.should be_empty
      with_captured_log { load_config(%([content.files]\nallow_extensions = ["pdf"]\n)) }.should_not contain("ignore")
    end

    it "loads without a [content.files] table, and beside one" do
      config = load_config(%([content]\nignore = ["x.md"]\n[content.files]\nallow_extensions = ["png"]\n))
      config.content_files.ignore.should eq(["x.md"])
      config.content_files.allow_extensions.should eq([".png"])
    end
  end

  describe "matching" do
    rules = Hwaro::Models::ContentFilesConfig.new
    rules.ignore = ["README.md", "_templates", "**/*.excalidraw.md", "drafts/*"]

    it "matches a root file only where the pattern says (* does not cross /)" do
      rules.ignored?("README.md").should be_true
      rules.ignored?("blog/README.md").should be_false
    end

    it "hides a whole subtree when a pattern matches its directory" do
      rules.ignored?("_templates/note.md").should be_true
      rules.ignored?("_templates/deep/x.png").should be_true
      rules.ignored?("drafts/sub/post.md").should be_true
      rules.ignored?("_templatesx/note.md").should be_false
    end

    it "matches ** at any depth, including the root" do
      rules.ignored?("x.excalidraw.md").should be_true
      rules.ignored?("a/b/x.excalidraw.md").should be_true
    end

    it "is case-sensitive, like disallow_paths" do
      rules.ignored?("readme.md").should be_false
    end

    # gitignore/globset spell a negated class `[!…]`; File.match? reads that
    # as "`!` or …", so `[!a]*` used to hide `a.md` and keep `b.md`.
    it "reads [!…] as a negated class, like [^…]" do
      config = load_config(%([content]\nignore = ["notes/[!_]*.md", "[^x]y.md"]\n))
      config.content_files.ignore.should eq(["notes/[^_]*.md", "[^x]y.md"])
      config.content_files.ignored?("notes/a.md").should be_true
      config.content_files.ignored?("notes/_tpl.md").should be_false
      config.content_files.ignored?("ay.md").should be_true
      config.content_files.ignored?("xy.md").should be_false
    end

    # gitignore's folder form: `_*` hides `_index.md` too, `_*/` does not.
    it "matches folders only for a pattern written with a trailing /" do
      folders = Hwaro::Models::ContentFilesConfig.new
      folders.ignore = ["_*/", "**/_*/", "drafts/"]
      folders.ignored?("_templates/note.md").should be_true
      folders.ignored?("blog/_partials/x.md").should be_true
      folders.ignored?("drafts/a.md").should be_true
      folders.ignored?("_index.md").should be_false
      folders.ignored?("blog/_index.md").should be_false
      folders.ignored?("drafts").should be_false
      files = Hwaro::Models::ContentFilesConfig.new
      files.ignore = ["_*"]
      files.ignored?("_index.md").should be_true
    end

    it "matches a pattern of any depth only where its segments line up" do
      deep = Hwaro::Models::ContentFilesConfig.new
      deep.ignore = ["a/*/c", "x?z", "{p,q/r}"]
      deep.ignored?("a/b/c/d.md").should be_true
      deep.ignored?("a/b/d.md").should be_false
      deep.ignored?("xyz/n.md").should be_true
      deep.ignored?("q/r/s.md").should be_true
      deep.ignored?("p").should be_true
      deep.ignored?("q/s.md").should be_false
    end

    it "never matches a path outside the content root" do
      wide = Hwaro::Models::ContentFilesConfig.new
      wide.ignore = ["**"]
      wide.ignored?("../config.toml").should be_false
      wide.ignored?("post.md").should be_true
    end

    it "makes an ignored file a denied one for the content-file lanes" do
      files = Hwaro::Models::ContentFilesConfig.new
      files.allow_extensions = [".png"]
      files.ignore = ["private"]
      files.publish?("private/a.png").should be_false
      files.denied?("private/data.json").should be_true
      files.publish?("public/a.png").should be_true
    end
  end
end
