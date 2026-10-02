# Renders *source* through a fresh Hwaro template environment (all custom
# filters, tests and functions registered), the way the build does.
def render_crinja(source : String, vars = {} of String => Crinja::Value) : String
  Crinja::Template.new(source, Hwaro::Content::Processors::TemplateEngine.new.env).render(vars)
end
