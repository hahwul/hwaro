# Renders *source* through a fresh Hwaro template environment (all custom
# filters, tests and functions registered), the way the build does — with
# `[templates] autoescape` at its default unless *autoescape* says otherwise.
def render_crinja(source : String, vars = {} of String => Crinja::Value, autoescape : Bool = Hwaro::Models::TemplatesConfig.new.autoescape) : String
  Crinja::Template.new(source, Hwaro::Content::Processors::TemplateEngine.new(autoescape).env).render(vars)
end
