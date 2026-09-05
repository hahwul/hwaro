require "../spec_helper"

# Load-order oracle for the file-split refactor.
#
# Every registry below is populated by hand-written literals or by top-level
# `register` calls, so its contents and ORDER are exactly what a bad merge or
# a mis-ordered `require` would silently change. Pinning them here turns
# "the split moved a require" into a failing example instead of a runtime
# surprise (a processor that stops handling `.md`, a hook that runs before
# the one it depends on, a CLI subcommand that vanishes from `--help`).
#
# When you intentionally add or reorder an entry, update the matching list.
describe "registration order" do
  it "keeps the content processor registry" do
    Hwaro::Content::Processors::Registry.all.map(&.name).should eq(
      ["markdown", "json", "html", "xml"]
    )
  end

  it "keeps the lifecycle hook order" do
    Hwaro::Content::Hooks.all.map(&.class.name).should eq([
      "Hwaro::Content::Hooks::SeoHooks",
      "Hwaro::Content::Hooks::TaxonomyHooks",
      "Hwaro::Content::Hooks::SassHooks",
      "Hwaro::Content::Hooks::AssetHooks",
      "Hwaro::Content::Hooks::PwaHooks",
      "Hwaro::Content::Hooks::AmpHooks",
      "Hwaro::Content::Hooks::OgImageHooks",
      "Hwaro::Content::Hooks::ImageHooks",
    ])
  end

  it "keeps the built-in scaffold registry" do
    Hwaro::Services::Scaffolds::Registry.all.map(&.type.to_s).should eq(
      ["simple", "bare", "blog", "docs", "book"]
    )
  end

  it "keeps the doctor check registry" do
    Hwaro::Services::CHECK_GROUPS.map(&.key).should eq([:config, :templates, :content])
    Hwaro::Services::CHECK_GROUPS.flat_map(&.checks.map(&.label)).should eq([
      "file present & parseable",
      "base_url, title",
      "sitemap (changefreq, priority)",
      "taxonomies (duplicates)",
      "search (format)",
      "languages (default_language resolves)",
      "versions (content paths exist)",
      "markdown / pwa (valid enums)",
      "image processing (widths set)",
      "deployment / related (refs resolve)",
      "menus (parent references)",
      "referenced files & dirs",
      "build output (route evidence)",
      "sass (sources & enablement)",
      "required files (page.html, section.html)",
      "template syntax",
      "directory present",
      "front matter (TOML/YAML parse)",
      "front matter menus (declared in config)",
      "section index files (_index.md)",
    ])
    Hwaro::Services::Doctor::KNOWN_ISSUE_IDS.size.should eq(34)
    Hwaro::Services::ALL_BLOCKING_IDS.to_a.sort.should eq(
      ["config-not-found", "config-parse-error", "content-dir-missing", "template-dir-missing"]
    )
  end

  it "keeps the CLI command set and tool subcommand order" do
    Hwaro::CLI::Runner.new
    Hwaro::CLI::CommandRegistry.names.should eq(
      ["build", "completion", "deploy", "doctor", "help", "init", "new", "serve", "tool", "version"]
    )
    Hwaro::CLI::Commands::ToolCommand.subcommands.map(&.name).should eq([
      "convert", "list", "check-links", "doctor", "platform", "ci",
      "import", "export", "stats", "validate", "unused-assets", "agents-md",
    ])
  end

  it "keeps the Crinja filter, test and function sets" do
    env = Hwaro::Content::Processors::TemplateEngine.new.env
    env.filters.keys.sort!.should eq(%w[
      abs absolute_url active_path append attr batch capitalize ceil center
      compact date default dictsort escape filesizeformat first flatten float
      floor forceescape format group_by groupby indent inspect int join
      jsonify last length list lower map markdownify pluralize pprint prepend
      random reject rejectattr relative_url replace reverse round safe select
      selectattr slice slugify sort sort_by split string strip_html striptags
      sum t title tojson trim truncate truncate_words unique upper urlencode
      urlize where wordcount wordwrap xml_escape xmlattr
    ])
    env.tests.keys.sort!.should eq(%w[
      callable containing defined divisibleby empty endswith equalto escaped
      even greaterthan in iterable lessthan lower mapping matching nil none
      number odd present sameas sequence startswith string undefined upper
    ])
    env.functions.keys.sort!.should eq(%w[
      asset asset_url cycler debug dict env get_menu get_page get_section
      get_taxonomy get_taxonomy_url get_url joiner load_data now range
      resize_image super url_for
    ])
  end

  it "keeps the config section loader order" do
    # The keys each loader reads, in load order. Three entries are order
    # sensitive (languages after menus/taxonomies, sass after auto_includes,
    # the deployment source-dir resolver after build + deployment); pinning
    # the whole sequence is simpler than pinning the constraints.
    Hwaro::Models::Config::SECTION_LOADERS.map(&.keys.join(",")).should eq(%w[
      sitemap robots llms feeds search plugins content content content
      pagination highlight auto_includes og menus taxonomies languages
      versions build serve markdown series related git permalinks assets
      sass pwa amp image_processing doctor static deployment
    ] + [""] + %w[outputs links data content])
  end

  it "keeps the config snippet registry" do
    Hwaro::Services::ConfigSnippets::SECTION_REGISTRY.keys.should eq(%w[
      plugins highlight og search serve pagination series related git markdown
      sitemap robots llms feeds build links permalinks auto_includes assets sass
      deployment image_processing pwa amp menus
    ])
  end

  it "keeps the known top-level config keys (scalars first, then sorted sections)" do
    Hwaro::Models::Config::KNOWN_TOP_LEVEL_KEYS.should eq(%w[
      title description base_url default_language
      amp assets auto_includes build content data deployment doctor feeds
      git highlight image_processing languages links llms markdown menus og
      outputs pagination permalinks plugins pwa related robots sass search
      series serve sitemap static taxonomies versions
    ])
  end
end
