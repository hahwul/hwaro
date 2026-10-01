# Doctor — templates/ diagnostics.
#
# Split out of doctor.cr, which keeps the require order, the Doctor ivars
# and `run`. Parts only define or reopen types: no requires, no load-time
# statements (scripts/check_no_toplevel_effects.sh).
module Hwaro
  module Services
    class Doctor
      # Check templates directory for required files.
      #
      # A missing `page` template or a syntax error ships a broken site
      # (raw fragments, or a render failure), so those are `:error` level
      # and CI gates on `doctor`'s exit code catch them before `hwaro build`
      # runs.
      #
      # Returns the loader names found (see `template_names`) so the
      # front-matter scan can check template references without walking
      # `templates/` a second time; nil when there is no `templates/`.
      private def check_templates(issues : Array(Issue)) : Set(String)?
        unless Dir.exists?(@templates_dir)
          issues << Issue.new(id: "template-dir-missing", level: :error, category: "template", file: nil,
            message: "Templates directory not found: #{@templates_dir}")
          return
        end

        files = template_files
        names = template_names(files)

        # `page` is the one template every page renders through; without it
        # (or the `default` the loader aliases into its slot) the build
        # writes raw, layout-less HTML fragments. `section` is not in
        # the same class: a section with no `section` template renders
        # through `page` (`determine_template`), so the build is fine and
        # only the section listing is lost. Reporting that as an error made
        # a site with no sections at all fail CI with no way to ignore it.
        unless names.includes?("page")
          issues << Issue.new(id: "template-required-missing", level: :error, category: "template", file: File.join(@templates_dir, "page.html"),
            message: "Required template file missing: page.html")
        end
        unless names.includes?("section")
          issues << Issue.new(id: "template-section-missing", level: :warning, category: "template", file: File.join(@templates_dir, "section.html"),
            message: "Template file missing: section.html — section pages (_index.md) render with the page template instead")
        end

        # Check template files for basic syntax errors
        files.each do |tpl_path|
          check_template_syntax(tpl_path, issues)
        end
        names
      end

      # Every file the template loader would pick up. `.html` alone missed
      # the other extensions `Builder::TEMPLATE_EXTENSION_REGEX` accepts
      # (`.j2`, `.jinja`, `.jinja2`, `.ecr`), so a site whose templates are
      # named `page.html.jinja` built fine but doctor reported the required
      # templates as missing — and never syntax-checked any of them.
      private def template_files : Array(String)
        Dir.glob(File.join(@templates_dir, "**", "*")).select do |path|
          next false unless path.matches?(Core::Build::Builder::TEMPLATE_EXTENSION_REGEX)
          # lstat first: `File.directory?` FOLLOWS symlinks, so a link
          # cycle anywhere under templates/ raised ELOOP out of the whole
          # doctor run. Mirror walk_section_dirs' guard — judge the entry
          # itself, and skip a symlink whose target can't be resolved.
          info = File.info?(path, follow_symlinks: false)
          next false unless info
          next info.file? unless info.symlink?
          target = begin
            File.info?(path, follow_symlinks: true)
          rescue ex : File::Error
            Logger.debug "Doctor: skipping unresolvable template symlink #{path}: #{ex.message}"
            nil
          end
          target ? target.file? : false
        end
      end

      # The loader key for a template file: path relative to `@templates_dir`,
      # minus one trailing template extension — exactly as
      # `Phases::Initialize#load_templates` computes it:
      #
      #   name = Path[path].relative_to("templates").gsub(TEMPLATE_EXTENSION_REGEX, "")
      #
      # Two consequences, both verified against the build with a marker in
      # the template body:
      #
      #   * `page.jinja` / `page.j2` load as "page" and ARE applied, while
      #     `page.html.jinja` loads as "page.html" and is NOT.
      #   * The name is the path RELATIVE to `templates/`, so
      #     `partials/page.html` loads as "partials/page" and cannot satisfy a
      #     root requirement.
      private def template_name(path : String) : String
        Path[path].relative_to(@templates_dir).to_s.gsub(Core::Build::Builder::TEMPLATE_EXTENSION_REGEX, "")
      end

      # Every name a page can render through. The loader copies `default`
      # into an absent `page` slot, so `default.html` alone renders every
      # page — and is what `template = "page"` resolves to.
      private def template_names(files : Array(String)) : Set(String)
        names = files.map { |path| template_name(path) }.to_set
        names << "page" if names.includes?("default")
        names
      end

      # Template syntax check, delegated to the actual Crinja parser used
      # by the build pipeline. The previous regex-based approach
      # (counting `{% if %}` vs `{% endif %}` etc.) couldn't catch:
      #  - paired tags it didn't enumerate (autoescape/raw/with/filter/…)
      #  - reordered close-before-open mistakes that still balanced
      #  - end tags whose name didn't match the opener
      # By instantiating `Crinja::Template` with `run_parser: true` we
      # surface every syntax error the build itself will hit, with line
      # and column numbers when Crinja attaches them. We do NOT render —
      # parse errors are the only failure class we want to gate on here.
      #
      # Unknown tags like {% details %} or {% my_custom %} are tolerated
      # (they are almost always project-specific shortcodes demonstrated
      # inside docs templates). Real syntax errors still fail hard.
      private def check_template_syntax(file_path : String, issues : Array(Issue))
        content = File.read(file_path)

        begin
          Crinja::Template.new(content, env: template_parse_env, filename: file_path, run_parser: true)
        rescue ex : Crinja::TemplateSyntaxError | Crinja::TemplateError
          issues << Issue.new(
            id: "template-syntax-error",
            level: :error,
            category: "template",
            file: file_path,
            message: format_crinja_error(ex),
          )
        end
      rescue ex
        msg = ex.message.to_s
        # Custom shortcodes (e.g. {% details %}, {% gallery %}) used inside
        # template files for documentation/demo purposes are expected to be
        # unknown to the bare Crinja parser used by doctor. These are not
        # real template syntax errors — the project provides the shortcode
        # implementation at build time via templates/shortcodes/*.html.
        if msg.includes?("no tag with name") && msg.includes?("registered")
          return
        end

        issues << Issue.new(id: "template-read-error", level: :error, category: "template", file: file_path,
          message: "Failed to read template: #{ex.message}")
      end

      private def template_parse_env : Crinja
        @template_parse_env ||= Crinja.new
      end

      private def format_crinja_error(ex : Crinja::Error) : String
        msg = (ex.message || ex.class.name).lines.first?.try(&.strip) || ex.class.name
        loc = ex.location_start
        loc ? "Template syntax error at line #{loc.line}, column #{loc.column}: #{msg}" : "Template syntax error: #{msg}"
      end
    end
  end
end
