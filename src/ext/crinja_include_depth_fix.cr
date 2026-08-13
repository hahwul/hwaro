# Monkey-patch for Crinja's `{% include %}` tag — kept here so we don't fork
# the vendored library, mirroring ext/crinja_resolve_fix.cr and
# ext/markd_entity_fix.cr.
#
# Upstream `Crinja::Tag::Include#interpret` (crinja 0.9.0,
# src/lib/tag/include.cr:43-49) goes straight from `env.get_template` to
# `template.render(io, context)` with nothing tracking how deep it already
# is:
#
#   template = env.get_template(include_name)
#   template.render(io, context)
#
# A template that includes itself — directly, or through a partial that
# includes it back — therefore recurses until the native stack is gone:
#
#   templates/partials/header.html: {% include "partials/nav.html" %}
#   templates/partials/nav.html:    {% include "partials/header.html" %}
#
# The process dies with `Stack overflow (e.g., infinite or very deep
# recursion)` and an ~8500-line backtrace (exit 11/132). Crystal cannot
# rescue a stack overflow, so every rescue in the build path is bypassed:
# `hwaro build` aborts uninformatively, and under `hwaro serve` the server
# process is killed outright by the first rebuild that sees the cycle and
# never comes back — a typo in a partial ends the session.
#
# Sibling tags degrade cleanly because they push onto the cycle-detection
# stacks `Crinja::Context` allocates for them (`extend_path_stack`,
# `import_path_stack`); `{% extends %}` reports `Tag cycle detected: extend`
# as HWARO_E_TEMPLATE / exit 4. `include_path_stack` is allocated, exposed
# and never pushed to.
#
# We deliberately do NOT wire that stack up. It raises on the first REPEAT
# of a name, which would also reject a terminating self-include (the way
# recursive menus are sometimes written), i.e. it would break sites that
# render correctly today. A depth cap only rejects nesting no real template
# tree has, and it must trip before the stack does rather than after: 64
# levels is an order of magnitude more than the deepest partial tree we have
# seen (single digits) and two orders below the ~850 include frames it took
# to exhaust an 8 MB fiber stack.
#
# `Crinja::RuntimeError` is a `Crinja::Error`, so the renderer attaches the
# offending template's file:line:col on the way out and hwaro's existing
# classification turns it into HWARO_E_TEMPLATE (exit 4) — the same clean
# failure `{% extends %}` cycles already produce, and one the serve rebuild
# rescue survives. The message carries the chain of templates that led here
# so the cycle can actually be found.
#
# Remove when: upstream pushes onto `include_path_stack` (or otherwise
# bounds include recursion) in `Tag::Include#interpret`.

require "crinja"

class Crinja
  # Templates entered through `{% include %}`, innermost last.
  #
  # This lives on the environment because that is the object that stays
  # identical across a nested include: `Tag::Include` renders through
  # `env.get_template(...)`, and `TemplateCache::InMemory` keys its entries
  # by env, so the template rendered inside an include always carries this
  # very instance. hwaro hands every render worker its own environment
  # (`Render#create_fresh_crinja_env`), so this array is never shared
  # between fibers.
  getter hwaro_include_chain : Array(String) = [] of String
end

class Crinja::Tag::Include < Crinja::Tag
  # Maximum `{% include %}` nesting. See the header: high enough that no
  # real template tree reaches it, low enough that the stack survives.
  HWARO_MAX_INCLUDE_DEPTH = 64

  private def interpret(io : IO, renderer : Crinja::Renderer, tag_node : TagNode)
    chain = renderer.env.hwaro_include_chain

    if chain.size >= HWARO_MAX_INCLUDE_DEPTH
      # Print the tail, not all 64 entries: a cycle repeats, so the last few
      # templates name every member of it, and the whole chain would bury the
      # file:line the renderer appends below the message.
      tail = chain.last(8)
      trail = tail.join(" -> ")
      trail = "... -> #{trail}" if chain.size > tail.size

      raise Crinja::RuntimeError.new(
        "Include nesting too deep (limit #{HWARO_MAX_INCLUDE_DEPTH}) — " \
        "a {% include %} cycle? Include chain: #{trail}"
      )
    end

    # Record the template the tag sits in, not the one it pulls in: the
    # target name is only known after upstream parses the tag arguments, and
    # a cycle shows up just as clearly as a repeat in this chain.
    template = renderer.template
    chain << (template.name.presence || template.filename || "<string>")

    begin
      previous_def
    ensure
      # Pop in `ensure`: environments are reused for every page a worker
      # renders, so a chain entry leaked by a failed render would count
      # against unrelated pages later.
      chain.pop
    end
  end
end
