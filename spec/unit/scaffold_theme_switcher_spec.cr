require "../spec_helper"
require "../../src/services/scaffolds/registry"

# The styled scaffolds auto-follow the OS color scheme (light-dark()
# tokens) and ship a manual 3-state switcher on top: auto → light → dark,
# persisted in localStorage as "hwaro-theme". These specs lock the three
# moving parts in for every styled scaffold:
#   * the pre-paint head script (no wrong-scheme flash on reload)
#   * the header toggle button with its three mode icons
#   * the footer cycle script and the [data-theme] CSS pin rules
describe "scaffold theme switcher" do
  simple = Hwaro::Services::Scaffolds::Simple.new
  blog = Hwaro::Services::Scaffolds::Blog.new
  docs = Hwaro::Services::Scaffolds::Docs.new
  book = Hwaro::Services::Scaffolds::Book.new

  it "applies the stored theme before first paint in every styled head" do
    {simple, blog, docs, book}.each do |scaffold|
      header = scaffold.template_files["header.html"]
      header.should contain(%(localStorage.getItem("hwaro-theme")))
      # The head applier runs inline before the stylesheet paints.
      header.should contain(%(document.documentElement.setAttribute("data-theme",t)))
    end
  end

  it "renders the toggle button with all three mode icons in the header chrome" do
    chrome = {
      simple => simple.template_files["header.html"],
      blog   => blog.template_files["partials/nav.html"],
      docs   => docs.template_files["partials/nav.html"],
      book   => book.template_files["partials/nav.html"],
    }
    chrome.each_value do |html|
      html.should contain(%(class="theme-toggle"))
      html.should contain(%(data-mode="auto"))
      html.should contain("tt-auto")
      html.should contain("tt-light")
      html.should contain("tt-dark")
    end
  end

  it "inlines the cycle script in every styled footer" do
    {simple, blog, docs, book}.each do |scaffold|
      footer = scaffold.template_files["footer.html"]
      footer.should contain(%(var MODES = ["auto", "light", "dark"]))
      footer.should contain(%(localStorage.setItem(KEY, mode)))
    end
  end

  it "pins the scheme via [data-theme] rules in every styled sheet" do
    sheets = {
      simple.template_files["header.html"],
      blog.static_files["css/style.css"],
      docs.static_files["css/style.css"],
      book.static_files["css/style.css"],
    }
    sheets.each do |css|
      css.should contain(%(:root[data-theme="light"] { color-scheme: light; }))
      css.should contain(%(:root[data-theme="dark"] { color-scheme: dark; }))
      css.should contain(".theme-toggle")
    end
  end

  it "leaves bare switcher-free (it ships no stylesheet or tokens)" do
    bare = Hwaro::Services::Scaffolds::Bare.new
    bare.template_files.each_value do |html|
      html.should_not contain("theme-toggle")
      html.should_not contain("hwaro-theme")
    end
  end
end
