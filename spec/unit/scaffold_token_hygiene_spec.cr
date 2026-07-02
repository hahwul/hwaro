require "../spec_helper"
require "../../src/services/scaffolds/registry"

# Token-hygiene lint for the scaffold design system.
#
# Every color in scaffold component CSS must flow through the DesignTokens
# vocabulary (light-dark() pairs in :root) — a single hardcoded hex/rgba
# outside a token definition breaks automatic dark theming for that rule.
# This spec mechanically locks "dark works everywhere" against regression.
#
# Allowed to carry literals:
#   * token-definition lines (`--foo: …`) — that's where colors live,
#     including per-scaffold layout hooks like `--bg-sidebar: light-dark(…)`
#   * the @supports feature-test condition itself
#   * @font-face blocks (no theme colors, but src/format noise)
private def color_violations(css : String) : Array(String)
  without_fonts = css.gsub(/@font-face\s*\{[^}]*\}/m, "")
  violations = [] of String
  without_fonts.each_line.with_index do |line, i|
    next if line =~ /^\s*--[a-zA-Z][a-zA-Z0-9-]*\s*:/
    next if line.includes?("@supports not (color: light-dark")
    next unless line =~ /#[0-9a-fA-F]{3,8}\b|rgba?\(/
    violations << "line #{i + 1}: #{line.strip}"
  end
  violations
end

private def external_sheet(scaffold) : String
  scaffold.static_files["css/style.css"]
end

describe "scaffold token hygiene" do
  it "simple's inlined sheet has no colors outside token definitions" do
    header = Hwaro::Services::Scaffolds::Simple.new.template_files["header.html"]
    css = header[/<style>(.*)<\/style>/m, 1]? || ""
    css.should_not be_empty
    color_violations(css).should be_empty
  end

  {% for pair in [{"blog", "Blog"}, {"docs", "Docs"}, {"book", "Book"}] %}
    it "{{ pair[0].id }}'s stylesheet has no colors outside token definitions" do
      css = external_sheet(Hwaro::Services::Scaffolds::{{ pair[1].id }}.new)
      color_violations(css).should be_empty
    end
  {% end %}

  {% for pair in [{"blog-dark", "BlogDark"}, {"docs-dark", "DocsDark"}, {"book-dark", "BookDark"}] %}
    it "{{ pair[0].id }}'s forced-dark sheet stays clean too" do
      css = external_sheet(Hwaro::Services::Scaffolds::{{ pair[1].id }}.new)
      color_violations(css).should be_empty
    end
  {% end %}
end
