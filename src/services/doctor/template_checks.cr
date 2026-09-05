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
      # All template-level problems here are build-blocking — Crinja
      # refuses to render if templates are missing or have syntax
      # errors — so they're emitted at `:error` level so CI gates on
      # `doctor`'s exit code catch them before `hwaro build` runs.
      private def check_templates(issues : Array(Issue))
        unless Dir.exists?(@templates_dir)
          issues << Issue.new(id: "template-dir-missing", level: :error, category: "template", file: nil,
            message: "Templates directory not found: #{@templates_dir}")
          return
        end

        %w[page.html section.html].each do |required|
          path = File.join(@templates_dir, required)
          unless template_present?(required)
            issues << Issue.new(id: "template-required-missing", level: :error, category: "template", file: path,
              message: "Required template file missing: #{required}")
          end
        end

        # Check template files for basic syntax errors
        template_files.each do |tpl_path|
          check_template_syntax(tpl_path, issues)
        end
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

      # A required template is present when some file in `templates/` loads
      # under its NAME, exactly as `Phases::Initialize` computes it:
      #
      #   name = Path[path].relative_to("templates").gsub(TEMPLATE_EXTENSION_REGEX, "")
      #
      # Two consequences the previous version got wrong, both verified against
      # the build with a marker in the template body:
      #
      #   * `page.jinja` / `page.j2` load as "page" and ARE applied; only
      #     comparing against the required name with its extension still
      #     attached (`"page.html"`) rejected them. `page.html.jinja` loads as
      #     "page.html", is NOT applied (the build silently falls back to the
      #     built-in default), and must therefore NOT satisfy the requirement.
      #   * The name is the path RELATIVE to `templates/`, so
      #     `partials/page.html` loads as "partials/page" and cannot satisfy a
      #     root requirement. Matching on `File.basename` hid a build-blocking
      #     error for a project whose only templates live in a subdirectory.
      private def template_present?(required : String) : Bool
        wanted = required.gsub(Core::Build::Builder::TEMPLATE_EXTENSION_REGEX, "")
        template_files.any? { |path| template_name(path) == wanted }
      end

      # The loader key for a template file: path relative to `@templates_dir`,
      # minus one trailing template extension.
      private def template_name(path : String) : String
        Path[path].relative_to(@templates_dir).to_s.gsub(Core::Build::Builder::TEMPLATE_EXTENSION_REGEX, "")
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
