require "../spec_helper"
require "../../src/services/scaffolds/registry"

# Specs for the self-contained asset story the styled scaffolds ship:
# embedded Charter (Charis SIL) webfonts and build-time syntax
# highlighting. Both exist so a generated site renders its signature
# serif and highlights code with **zero external requests** — these
# specs lock that promise in.
describe "Scaffold embedded assets" do
  describe "embedded webfonts" do
    it "ships the three Charis SIL faces plus the OFL license (styled scaffolds)" do
      {
        Hwaro::Services::Scaffolds::Simple.new,
        Hwaro::Services::Scaffolds::Blog.new,
        Hwaro::Services::Scaffolds::Docs.new,
        Hwaro::Services::Scaffolds::Book.new,
        Hwaro::Services::Scaffolds::BlogDark.new,
      }.each do |scaffold|
        files = scaffold.static_files
        files.has_key?("fonts/charis-sil-400.woff2").should be_true
        files.has_key?("fonts/charis-sil-700.woff2").should be_true
        files.has_key?("fonts/charis-sil-italic.woff2").should be_true
        files.has_key?("fonts/OFL.txt").should be_true
      end
    end

    it "emits valid woff2 bytes (base64 round-trips to the wOF2 signature)" do
      files = Hwaro::Services::Scaffolds::Blog.new.static_files
      # woff2 files start with the ASCII magic "wOF2".
      files["fonts/charis-sil-400.woff2"][0, 4].should eq("wOF2")
      files["fonts/charis-sil-700.woff2"][0, 4].should eq("wOF2")
      files["fonts/charis-sil-italic.woff2"][0, 4].should eq("wOF2")
    end

    it "ships the SIL Open Font License text beside the fonts" do
      ofl = Hwaro::Services::Scaffolds::Docs.new.static_files["fonts/OFL.txt"]
      ofl.should contain("SIL Open Font License")
      ofl.should contain("Charis")
    end

    it "leaves bare font-free (no stylesheet references them)" do
      Hwaro::Services::Scaffolds::Bare.new.static_files.keys.should eq(["favicon.svg"])
    end

    it "binds the embedded faces to family \"Charter\", local() first (no download when Charter exists)" do
      css = Hwaro::Services::Scaffolds::Blog.new.static_files["css/style.css"]
      css.should contain("@font-face")
      css.should contain(%(font-family: "Charter"))
      # local() precedes url() so a machine with Charter skips the fetch.
      css.should contain(%(local("Charter"), local("Charis SIL"), url("../fonts/charis-sil-400.woff2")))
    end

    it "points the simple scaffold's inline @font-face at a base_url-prefixed path" do
      # simple inlines its CSS in a template, so it can (and must) use
      # {{ base_url }}; blog/docs/book use a relative ../fonts path instead.
      header = Hwaro::Services::Scaffolds::Simple.new.template_files["header.html"]
      header.should contain("@font-face")
      header.should contain(%(url("{{ base_url }}/fonts/charis-sil-400.woff2")))
    end
  end

  describe "internalized syntax highlighting" do
    it "defaults to build-time highlighting (mode = \"server\")" do
      {
        Hwaro::Services::Scaffolds::Simple.new,
        Hwaro::Services::Scaffolds::Blog.new,
        Hwaro::Services::Scaffolds::Docs.new,
        Hwaro::Services::Scaffolds::Book.new,
        Hwaro::Services::Scaffolds::BlogDark.new,
        Hwaro::Services::Scaffolds::DocsDark.new,
        Hwaro::Services::Scaffolds::BookDark.new,
      }.each do |scaffold|
        scaffold.config_content.should contain(%(mode = "server"))
      end
    end

    it "inlines the syntax theme into the stylesheet (no external theme link)" do
      css = Hwaro::Services::Scaffolds::Blog.new.static_files["css/style.css"]
      css.should contain(".hljs-keyword")
      css.should contain(".hljs-string")
    end

    it "drops the highlight stylesheet link and any CDN reference from the chrome" do
      header = Hwaro::Services::Scaffolds::Blog.new.template_files["header.html"]
      header.should_not contain("{{ highlight_css }}")
      header.should_not contain("cdnjs")
    end
  end
end
