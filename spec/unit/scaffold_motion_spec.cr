require "../spec_helper"
require "../../src/services/scaffolds/simple"

# The modern motion layer shipped by the shared base templates: cross-document
# view transitions, the @starting-style entry reveal, and the sticky glass
# masthead. Each promise here is a progressive enhancement, so the specs also
# lock the guards (reduced-motion opt-outs, backdrop-filter fallback) that keep
# the scaffold correct on browsers and users that opt out.
describe "scaffold motion layer" do
  header = Hwaro::Services::Scaffolds::Simple.new.template_files["header.html"]

  it "enables cross-document view transitions with a reduced-motion opt-out" do
    header.should contain("@view-transition { navigation: auto; }")
    reduce_block = header.partition("@media (prefers-reduced-motion: reduce)")[2]
    reduce_block.should contain("@view-transition { navigation: none; }")
  end

  it "reveals the page via @starting-style only when motion is allowed" do
    prefer_block = header.partition("@media (prefers-reduced-motion: no-preference)")[2]
    prefer_block.should contain("@starting-style")
    prefer_block.should contain(".site-main { opacity: 0;")
  end

  it "ships a sticky glass masthead with a backdrop-filter fallback" do
    header_rule = header.partition(".site-header {")[2]
    header_rule.should contain("position: sticky;")
    header_rule.should contain("backdrop-filter: var(--glass-filter);")
    header.should contain("@supports not ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px)))")
  end

  it "keeps anchor targets clear of the sticky masthead" do
    header.should contain("scroll-margin-top")
  end

  it "halts animations as well as transitions under reduced motion" do
    reduce_block = header.partition("@media (prefers-reduced-motion: reduce)")[2]
    reduce_block.should contain("animation-duration: 0.01ms !important;")
  end
end
