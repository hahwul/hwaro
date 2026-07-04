require "./support/build_helper"
require "../../src/services/scaffolds/blog"
require "../../src/services/scaffolds/simple"

# The blog and simple scaffolds' header nav used to hardcode links, with an
# inert `{% raw %}...{% endraw %}`-wrapped comment showing how to swap in a
# dynamic `site.sections` loop by hand. The first-class menu system replaced
# both: [[menus.main]] in config.toml (or a page/section's own front matter)
# feeds a REAL `get_menu(name="main")` loop, so there's no more hand-copied
# example to keep inert — the loop just runs. These tests build the real
# scaffolds (via their DEFAULT `hwaro init` config path — see
# `build_balanced_default_config` / `minimal_config_content` — not just the
# `--full-config` `config_content` path) and assert the nav renders working
# links with no unrendered Jinja syntax leaking into the output.
describe "Scaffold nav (menu system)" do
  it "blog scaffold renders config-driven nav links with no leaked template syntax" do
    scaffold = Hwaro::Services::Scaffolds::Blog.new
    build_site(
      scaffold.minimal_config_content,
      content_files: scaffold.content_files,
      template_files: scaffold.template_files,
      static_files: scaffold.static_files,
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<a href="/posts/">Posts</a>))
      html.should contain(%(<a href="/archives/">Archives</a>))
      html.should contain(%(<a href="/about/">About</a>))
      html.should_not contain("{% raw %}")
      html.should_not contain("{% endraw %}")
      html.should_not contain("{% for ")
      html.should_not contain("get_menu(")
    end
  end

  it "simple scaffold renders config-driven nav links, with the homepage flagged active" do
    scaffold = Hwaro::Services::Scaffolds::Simple.new
    build_site(
      scaffold.minimal_config_content,
      content_files: scaffold.content_files,
      template_files: scaffold.template_files,
      static_files: scaffold.static_files,
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<a href="/" aria-current="page">Home</a>))
      html.should contain(%(<a href="/about/">About</a>))
      html.should_not contain("{% raw %}")
      html.should_not contain("{% endraw %}")
      html.should_not contain("{% for ")
      html.should_not contain("get_menu(")
    end
  end

  it "blog scaffold's --full-config path (config_content) also renders the same nav links" do
    scaffold = Hwaro::Services::Scaffolds::Blog.new
    build_site(
      scaffold.config_content,
      content_files: scaffold.content_files,
      template_files: scaffold.template_files,
      static_files: scaffold.static_files,
    ) do
      html = File.read("public/index.html")
      html.should contain(%(<a href="/posts/">Posts</a>))
      html.should contain(%(<a href="/archives/">Archives</a>))
      html.should contain(%(<a href="/about/">About</a>))
    end
  end
end
