require "../support/build_helper"

# =============================================================================
# Regression coverage for ext/crinja_include_depth_fix.cr.
#
# `{% include %}` had no recursion guard at all, so a partial that included
# itself (directly or through another partial) recursed until the native
# stack was gone: SIGSEGV, ~8500 backtrace lines, exit 11 — bypassing every
# rescue in the build path, and killing `hwaro serve` outright. It must fail
# the way `{% extends %}` cycles already do: HWARO_E_TEMPLATE, with the
# include chain named so the cycle can be found.
# =============================================================================

describe "Template include cycles" do
  it "reports a mutually recursive include as a template error" do
    err = expect_raises(Hwaro::HwaroError) do
      build_site(
        BASIC_CONFIG,
        content_files: {"index.md" => "---\ntitle: Home\n---\nhello"},
        template_files: {
          "page.html"            => %(<html>{% include "partials/header.html" %}</html>),
          "partials/header.html" => %(<header>{% include "partials/nav.html" %}</header>),
          "partials/nav.html"    => %(<nav>{% include "partials/header.html" %}</nav>),
        },
      ) { }
    end

    err.code.should eq(Hwaro::Errors::HWARO_E_TEMPLATE)
    message = err.message.not_nil!
    message.should contain("Include nesting too deep")
    # The chain must name both partials in the cycle.
    message.should contain("partials/header.html")
    message.should contain("partials/nav.html")
  end

  it "reports a self-including template as a template error" do
    err = expect_raises(Hwaro::HwaroError) do
      build_site(
        BASIC_CONFIG,
        content_files: {"index.md" => "---\ntitle: Home\n---\nhello"},
        template_files: {
          "page.html"          => %(<html>{% include "partials/self.html" %}</html>),
          "partials/self.html" => %(<div>{% include "partials/self.html" %}</div>),
        },
      ) { }
    end

    err.code.should eq(Hwaro::Errors::HWARO_E_TEMPLATE)
    err.message.not_nil!.should contain("Include nesting too deep")
  end

  it "still renders a partial included from several templates" do
    # The guard counts nesting depth, not repeated names, so a shared partial
    # pulled in by more than one template (the ordinary case) is untouched.
    build_site(
      BASIC_CONFIG,
      content_files: {"index.md" => "---\ntitle: Home\n---\nhello"},
      template_files: {
        "page.html"            => %({% include "partials/a.html" %}{% include "partials/b.html" %}{% include "partials/shared.html" %}),
        "partials/a.html"      => %(A{% include "partials/shared.html" %}),
        "partials/b.html"      => %(B{% include "partials/shared.html" %}),
        "partials/shared.html" => "S",
      },
    ) do
      File.read("public/index.html").should contain("ASBSS")
    end
  end
end
