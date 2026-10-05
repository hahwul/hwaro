require "../../../spec_helper"

private BASE = "title = \"T\"\nbase_url = \"http://localhost\"\n"

describe Hwaro::Models::SearchConfig do
  it "defaults the heading split, facets and UI to off" do
    search = Hwaro::Models::SearchConfig.new
    search.split_by_heading.should be_false
    search.facets.should be_empty
    search.ui.should be_false
    search.ui_enabled?.should be_false
  end

  it "parses split_by_heading, facets and ui" do
    config = load_config(BASE + <<-TOML)
      [search]
      enabled = true
      split_by_heading = true
      facets = ["section", "lang", "tags", "section"]
      ui = true
      TOML
    config.search.split_by_heading.should be_true
    config.search.facets.should eq(["section", "lang", "tags"])
    config.search.ui_enabled?.should be_true
  end

  it "accepts taxonomy facets and drops unknown names with a warning" do
    log = with_captured_log do
      config = load_config(BASE + <<-TOML)
        [search]
        enabled = true
        facets = ["category", "nope", "url", "tags"]

        [[taxonomies]]
        name = "category"
        TOML
      config.search.facets.should eq(["category", "tags"])
    end
    log.should contain("Ignoring unknown [search] facets nope, url (valid: section, lang, tags, category)")
  end

  it "rejects ui = true with a *_javascript format" do
    err = expect_config_error(BASE + <<-TOML)
      [search]
      enabled = true
      format = "fuse_javascript"
      ui = true
      TOML
    err.message.to_s.should contain("needs a JSON index")
    err.hint.to_s.should contain("fuse_json")
  end

  it "accepts ui with either JSON format and warns when search is disabled" do
    load_config(BASE + "[search]\nenabled = true\nformat = \"elasticlunr_json\"\nui = true\n").search.ui_enabled?.should be_true
    log = with_captured_log do
      load_config(BASE + "[search]\nui = true\n").search.ui_enabled?.should be_false
    end
    log.should contain("ui = true has no effect")
  end

  it "does not reject a *_javascript format while search is disabled" do
    log = with_captured_log do
      load_config(BASE + "[search]\nenabled = false\nformat = \"fuse_javascript\"\nui = true\n").search.ui_enabled?.should be_false
    end
    log.should contain("ui = true has no effect")
  end
end
