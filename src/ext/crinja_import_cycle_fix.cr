# `{% import "macros.html" as m %}` pushed the name onto the context's
# import cycle stack and never popped it, so the SECOND import of the same
# file in one render failed with `Tag cycle detected: import`: a base
# layout and the child that extends it each importing their macros, or two
# imports under different names. Jinja2 allows both. The name is popped once
# the import finishes, so the stack holds only imports still in progress —
# a real cycle (`a` imports `b` imports `a`) is still reported.
class Crinja::Tag::Import < Crinja::Tag
  private def interpret(io : IO, renderer : Renderer, tag_node : TagNode)
    stack = renderer.env.context.import_path_stack
    previous_def
    stack.pop
  end
end
