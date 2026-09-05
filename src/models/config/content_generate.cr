# Config section — [[content.generate]].
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    # One `[[content.generate]]` entry — a declarative rule that materializes
    # each record of a `site.data` array (disk `data/` or `[[data.remote]]`)
    # into a real content page. This class is the validated config shape;
    # evaluation and page synthesis live in `Core::Build::ContentGenerate`.
    #
    # `slug`/`title`/`body`/`date`/`description` and each `taxonomies` value
    # accept either a plain record field name ("sku") or a Crinja template
    # ("{{ item.sku | slugify }}") — a string containing `{{` or `{%` is
    # treated as a template rendered with the record bound to `item`.
    class ContentGenerateConfig
      # Dotted path into `site.data` naming the record array, e.g.
      # "products" or "products.items".
      property source : String
      # Target section: generated pages get paths `<section>/<slug>.md`, so
      # section listings, `[permalinks]` patterns, feeds and taxonomies all
      # apply exactly as they do to authored pages in that section.
      property section : String
      # Field-or-template producing each page's slug (slugified after
      # evaluation) and title.
      property slug : String
      property title : String
      # Field-or-template producing the page's markdown body ("" when nil
      # and no body_template).
      property body : String?
      # Alternative body source: a template file (from templates/) rendered
      # with the record as `item`. Mutually exclusive with `body`.
      property body_template : String?
      # Optional field-or-templates for front-matter date / description.
      property date : String?
      property description : String?
      # taxonomy name => field-or-template. A field that holds an array
      # contributes every element as a term; scalars contribute one term.
      property taxonomies : Hash(String, String)

      def initialize(@source : String, @section : String, @slug : String, @title : String)
        @body = nil
        @body_template = nil
        @date = nil
        @description = nil
        @taxonomies = {} of String => String
      end
    end
  end
end

module Hwaro
  module Models
    class Config
      # `[[content.generate]]` — declarative content generation from
      # `site.data` arrays (see ContentGenerateConfig). Shape errors are hard
      # errors, mirroring [[data.remote]]: a typo'd rule would otherwise
      # silently generate no pages.
      private def self.load_content_generate(config : Config)
        return unless content_section = config.raw["content"]?.try(&.as_h?)
        return unless generate_any = content_section["generate"]?

        generate_list = generate_any.as_a? ||
                        raise generate_config_error("'content.generate' must be an array of tables — declare each rule with [[content.generate]] (double brackets).")

        known_keys = %w[source section slug title body body_template date description taxonomies]

        config.content_generate = generate_list.map_with_index do |entry_any, index|
          where = "[[content.generate]] entry #{index + 1}"
          entry = entry_any.as_h? ||
                  raise generate_config_error("#{where} must be a table ([[content.generate]] with source/section/slug/title fields).")

          source = entry["source"]?.try(&.as_s?).try(&.strip).presence ||
                   raise generate_config_error("#{where} is missing the required string 'source' (a site.data key such as \"products\" or \"products.items\").")
          where = "[[content.generate]] \"#{source}\""
          unless source.matches?(/\A[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*\z/)
            raise generate_config_error("#{where}: source must be a dotted site.data path — segments of letters, digits, '_' and '-' joined with '.'.")
          end

          entry.each_key do |key|
            Logger.warn "#{where}: unknown key '#{key}' is ignored." unless known_keys.includes?(key)
          end

          section_raw = entry["section"]?.try(&.as_s?).try(&.strip.strip('/')).presence ||
                        raise generate_config_error("#{where} is missing the required string 'section' (the section generated pages are placed under, e.g. \"products\").")
          if section_raw.split('/').any? { |seg| seg.empty? || seg == "." || seg == ".." } ||
             section_raw.includes?('\\') || section_raw.includes?('\0')
            raise generate_config_error("#{where}: section \"#{section_raw}\" must be a relative path of non-empty segments without '.' or '..'.")
          end

          slug = entry["slug"]?.try(&.as_s?).try(&.strip).presence ||
                 raise generate_config_error("#{where} is missing the required string 'slug' (a record field name or a template such as \"{{ item.id }}\").")
          title = entry["title"]?.try(&.as_s?).try(&.strip).presence ||
                  raise generate_config_error("#{where} is missing the required string 'title' (a record field name or a template).")

          rule = ContentGenerateConfig.new(source, section_raw, slug, title)

          if body_any = entry["body"]?
            rule.body = body_any.as_s? ||
                        raise generate_config_error("#{where}: 'body' must be a string (a record field name or a template).")
          end
          if body_template_any = entry["body_template"]?
            rule.body_template = body_template_any.as_s?.try(&.strip).presence ||
                                 raise generate_config_error("#{where}: 'body_template' must be a non-empty template name from templates/.")
          end
          if rule.body && rule.body_template
            raise generate_config_error("#{where}: 'body' and 'body_template' are mutually exclusive — pick the record field/template string OR the template file.")
          end
          if date_any = entry["date"]?
            rule.date = date_any.as_s? ||
                        raise generate_config_error("#{where}: 'date' must be a string (a record field name or a template).")
          end
          if description_any = entry["description"]?
            rule.description = description_any.as_s? ||
                               raise generate_config_error("#{where}: 'description' must be a string (a record field name or a template).")
          end
          if taxonomies_any = entry["taxonomies"]?
            taxonomies = taxonomies_any.as_h? ||
                         raise generate_config_error("#{where}: 'taxonomies' must be a table of taxonomy name to record field/template, e.g. taxonomies = { tags = \"categories\" }.")
            taxonomies.each do |name, value_any|
              value = value_any.as_s? ||
                      raise generate_config_error("#{where}: taxonomies.#{name} must be a string (a record field name or a template).")
              rule.taxonomies[name] = value
            end
          end

          rule
        end
      end

      private def self.generate_config_error(message : String) : Hwaro::HwaroError
        Hwaro::HwaroError.new(
          code: Hwaro::Errors::HWARO_E_CONFIG,
          message: message,
          hint: "Each [[content.generate]] rule needs source + section + slug + title; optional: body OR body_template, date, description, taxonomies (table). Field values are record field names, or Crinja templates when they contain {{ or {%.",
        )
      end
    end
  end
end
