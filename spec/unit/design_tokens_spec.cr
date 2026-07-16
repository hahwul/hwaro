require "../spec_helper"
require "../../src/services/scaffolds/design_tokens"

private CANONICAL_TOKENS = %w[
  --primary --primary-strong --primary-tint --selection
  --rule-from --rule-to
  --heading --text --text-secondary --text-muted
  --bg --bg-subtle --bg-raised --bg-code --border --border-subtle
  --edge --glass --scrim
  --warn --ok
  --code-comment --code-keyword --code-string --code-number
  --code-func --code-type --code-variable --code-attr --code-symbol
  --step--1 --step-0 --step-1 --step-2 --step-3 --step-4 --step-5
  --space-1 --space-2 --space-3 --space-4 --space-5 --space-6 --space-7 --space-8
  --measure --radius --radius-sm
  --shadow-sm --shadow --shadow-lg
  --ease-out --transition --transition-slow --glass-filter
  --font-serif --font-sans --font-mono
]

describe Hwaro::Services::Scaffolds::DesignTokens do
  describe ".root_block" do
    it "declares every canonical token" do
      css = Hwaro::Services::Scaffolds::DesignTokens.root_block
      CANONICAL_TOKENS.each do |token|
        css.should contain("#{token}:")
      end
    end

    it "opts into both schemes and pairs the brand anchors with light-dark()" do
      css = Hwaro::Services::Scaffolds::DesignTokens.root_block
      css.should contain("color-scheme: light dark;")
      css.should contain("light-dark(#b35454, #ec7a66)")
      css.should contain("light-dark(#faf8f4, #141110)")
    end

    it "ships the [data-theme] pin rules the theme switcher drives" do
      css = Hwaro::Services::Scaffolds::DesignTokens.root_block
      css.should contain(%(:root[data-theme="light"] { color-scheme: light; }))
      css.should contain(%(:root[data-theme="dark"] { color-scheme: dark; }))
    end

    it "ships the static-light @supports fallback for pre-light-dark() browsers" do
      css = Hwaro::Services::Scaffolds::DesignTokens.root_block
      css.should contain("@supports not (color: light-dark(#000, #fff))")
      # color-mix-derived tokens are pinned statically too, so even
      # pre-color-mix browsers resolve them.
      css.should contain("--primary-tint: rgba(179, 84, 84, 0.08);")
      css.should contain("--glass: rgba(250, 248, 244, 0.85);")
    end

    it "injects layout lines inside :root" do
      css = Hwaro::Services::Scaffolds::DesignTokens.root_block("--header-h: 52px;\n--content-max-w: 860px;")
      root_part = css.split("@supports").first
      root_part.should contain("--header-h: 52px;")
      root_part.should contain("--content-max-w: 860px;")
      # The injection lands before :root closes.
      root_part.index!("--header-h").should be < root_part.index!("}")
    end

    it "is deterministic" do
      a = Hwaro::Services::Scaffolds::DesignTokens.root_block("--x: 1px;")
      b = Hwaro::Services::Scaffolds::DesignTokens.root_block("--x: 1px;")
      a.should eq(b)
    end
  end

  describe ".highlight_css" do
    it "colors hljs classes exclusively through --code-* tokens" do
      css = Hwaro::Services::Scaffolds::DesignTokens.highlight_css
      css.should contain(".hljs-keyword")
      css.should contain("var(--code-keyword)")
      css.should contain("var(--code-string)")
      css.should_not match(/#[0-9a-f]{3,8}/i)
    end
  end

  describe ".theme_toggle_css" do
    it "styles the switcher exclusively through tokens and shows one icon per mode" do
      css = Hwaro::Services::Scaffolds::DesignTokens.theme_toggle_css
      css.should contain(".theme-toggle")
      css.should contain(%(.theme-toggle[data-mode="auto"] .tt-auto))
      css.should contain(%(.theme-toggle[data-mode="light"] .tt-light))
      css.should contain(%(.theme-toggle[data-mode="dark"] .tt-dark))
      css.should_not match(/#[0-9a-f]{3,8}/i)
    end
  end
end
