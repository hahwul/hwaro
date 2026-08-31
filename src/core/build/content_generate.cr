# `[[content.generate]]` — materialize `site.data` records into content pages.
#
# Each rule names an array under `site.data` (a `data/` file or a
# `[[data.remote]]` payload) and field-or-template specs for the page's
# slug/title/body. Planning happens here, PURE: config + assembled data in,
# `Plan` records out. The build glue (ReadContent#synthesize_generated_pages)
# turns each plan into a `Models::Page` carrying a `Models::Page::Synthesis`,
# and from that point the page IS ordinary content — it parses, transforms
# and renders exactly like an authored file, so permalinks, taxonomies,
# feeds, search, sitemap, OG/AMP and output formats all apply. That is the
# design contract: synthesized pages must NEVER reuse the `generated` flag,
# which marks the synthetic taxonomy listing pages every content surface
# deliberately excludes.
#
# Field-or-template semantics (the convenience contract):
#   - A spec containing `{{` or `{%` is a Crinja template rendered with the
#     record bound to `item` (autoescape stays OFF, as everywhere in hwaro).
#   - Any other spec is a record FIELD NAME (dotted for nesting). A missing
#     field is a hard per-record error naming the rule, the record's index
#     and the available keys — typo protection; a field that exists but
#     holds null/"" simply omits the optional value (data reality: not
#     every record carries a date).
#
# Every error message names `[[content.generate]] "<source>"` and, where a
# record is involved, `record #N` (1-based, in data order) — a 500-record
# source must point at the one bad record, not at config.toml.

require "crinja"
require "../../models/config"
require "../../models/page"
require "../../utils/text_utils"
require "../../utils/frontmatter_writer"
require "../../utils/errors"
require "../../utils/nesting"

module Hwaro
  module Core
    module Build
      module ContentGenerate
        extend self

        # One planned page, ready to materialize. `path` is the synthetic
        # content-relative path (`<section>/<slug>.md`) — it drives
        # `PermalinkResolver` exactly like an authored file's path, so
        # `[permalinks]` patterns for the section apply unchanged.
        record Plan,
          path : String,
          section : String,
          slug : String,
          title : String,
          markdown : String,
          item : Crinja::Value,
          origin : String,
          date_raw : String?

        # Evaluate every rule against the assembled `site.data`.
        #
        # `env` must carry hwaro's filters (and, when `include_bodies` is
        # true and a rule uses `body_template`, the template loader) — the
        # build passes its own environment. `include_bodies: false` skips
        # body evaluation entirely for callers that only need identities
        # (`hwaro tool list`).
        def plan(config : Models::Config, data : Hash(String, Crinja::Value),
                 env : Crinja, include_bodies : Bool = true) : Array(Plan)
          rules = config.content_generate
          return [] of Plan if rules.empty?

          plans = [] of Plan
          # path => "…" descriptor of the claim, for cross-rule collisions.
          claimed = {} of String => String
          rules.each do |rule|
            plan_rule(rule, data, env, plans, claimed, include_bodies)
          end
          plans
        end

        private def plan_rule(rule : Models::ContentGenerateConfig,
                              data : Hash(String, Crinja::Value),
                              env : Crinja,
                              plans : Array(Plan),
                              claimed : Hash(String, String),
                              include_bodies : Bool)
          where = "[[content.generate]] \"#{rule.source}\""
          records = resolve_source_records(rule.source, data, where)
          return if records.empty?

          # Compile each template spec once per rule, render once per record.
          template_cache = {} of String => Crinja::Template

          body_template = nil
          if include_bodies && (name = rule.body_template)
            body_template = begin
              env.get_template(name)
            rescue ex : Crinja::Error | Crinja::TemplateNotFoundError
              # TemplateNotFoundError inherits Exception directly, NOT
              # Crinja::Error — a bare Crinja::Error rescue misses it.
              raise generate_error("#{where}: body_template \"#{name}\" could not be loaded: #{ex.message}")
            end
          end

          records.each_with_index do |item, index|
            record_where = "#{where}: record ##{index + 1}"

            slug_raw = eval_spec(rule.slug, item, env, template_cache, "#{record_where}: slug") ||
                       raise generate_error("#{record_where}: slug evaluated to nothing — field '#{rule.slug}' holds null/empty.")
            slug = Utils::TextUtils.slugify(slug_raw)
            if slug.empty?
              raise generate_error("#{record_where}: slug \"#{slug_raw}\" slugifies to \"\" — it has no letters or digits.")
            end
            record_where = "#{where}: record ##{index + 1} (\"#{slug}\")"

            title = eval_spec(rule.title, item, env, template_cache, "#{record_where}: title") ||
                    raise generate_error("#{record_where}: title evaluated to nothing — field '#{rule.title}' holds null/empty.")

            date_raw = rule.date.try { |spec| eval_spec(spec, item, env, template_cache, "#{record_where}: date") }
            description = rule.description.try { |spec| eval_spec(spec, item, env, template_cache, "#{record_where}: description") }

            taxonomies = {} of String => Array(String)
            rule.taxonomies.each do |taxonomy_name, spec|
              terms = eval_terms(spec, item, env, template_cache, "#{record_where}: taxonomies.#{taxonomy_name}")
              taxonomies[taxonomy_name] = terms unless terms.empty?
            end

            body = ""
            if include_bodies
              if spec = rule.body
                body = eval_spec(spec, item, env, template_cache, "#{record_where}: body") || ""
              elsif tmpl = body_template
                body = begin
                  tmpl.render({"item" => item})
                rescue ex : Crinja::Error
                  raise generate_error("#{record_where}: body_template \"#{rule.body_template}\" failed to render: #{ex.message}")
                end
              end
            end

            path = "#{rule.section}/#{slug}.md"
            if prev = claimed[path]?
              raise generate_error("#{record_where} produces '#{path}', already claimed by #{prev} — slugs must be unique across [[content.generate]] rules.")
            end
            claimed[path] = record_where

            plans << Plan.new(
              path: path,
              section: rule.section,
              slug: slug,
              title: title,
              markdown: synthetic_markdown(title, description, date_raw, taxonomies, body),
              item: item,
              origin: "data.#{rule.source}",
              date_raw: date_raw,
            )
          end
        end

        # Resolve the rule's dotted `source` path into an array of records.
        # Missing keys and non-array values are hard errors that spell out
        # what WAS found — "generated zero pages, silently" is the failure
        # mode this feature must never have.
        private def resolve_source_records(source : String, data : Hash(String, Crinja::Value), where : String) : Array(Crinja::Value)
          parts = source.split('.')
          current = data[parts.first]? ||
                    raise generate_error("#{where}: site.data.#{parts.first} is missing — no data/ file or [[data.remote]] key provides it#{data.empty? ? "" : " (available: #{data.keys.sort!.first(8).join(", ")})"}.")

          parts.each_with_index do |part, i|
            next if i.zero?
            walked = "site.data.#{parts[0..i - 1].join('.')}"
            child = begin
              current[part]
            rescue Crinja::Error
              raise generate_error("#{where}: #{walked} is #{type_name(current)}, not a table — cannot descend into '.#{part}'.")
            end
            if child.raw.is_a?(Crinja::Undefined)
              raise generate_error("#{where}: #{walked} has no key '#{part}'#{available_keys_hint(current)}.")
            end
            current = child
          end

          begin
            current.as_a
          rescue Crinja::Error
            raise generate_error("#{where}: site.data.#{source} is #{type_name(current)} — 'source' must name an array of records.")
          end
        end

        # Field-or-template evaluation to an optional scalar string.
        # Returns nil for null/empty values (the "omit the optional field"
        # path); raises for a MISSING field or a non-scalar value.
        private def eval_spec(spec : String, item : Crinja::Value, env : Crinja,
                              template_cache : Hash(String, Crinja::Template),
                              where : String) : String?
          if template_spec?(spec)
            rendered = render_spec(spec, item, env, template_cache, where)
            return rendered.empty? ? nil : rendered
          end

          value = lookup_field(item, spec, where)
          raw = value.raw
          case raw
          when Nil then nil
          when Array, Hash
            raise generate_error("#{where}: field '#{spec}' is #{type_name(value)}, not a scalar — use a template to derive a string from it.")
          when Time
            Utils::FrontmatterWriter.serialize_time(raw)
          else
            s = value.to_string
            s.empty? ? nil : s
          end
        end

        # Taxonomy variant of eval_spec: an array field contributes every
        # element as a term, a scalar contributes one, null/"" contributes
        # none. A template renders to a single term.
        private def eval_terms(spec : String, item : Crinja::Value, env : Crinja,
                               template_cache : Hash(String, Crinja::Template),
                               where : String) : Array(String)
          if template_spec?(spec)
            rendered = render_spec(spec, item, env, template_cache, where)
            return rendered.empty? ? [] of String : [rendered]
          end

          value = lookup_field(item, spec, where)
          case raw = value.raw
          when Nil then [] of String
          when Array
            raw.compact_map do |elem|
              elem_value = Crinja::Value.new(elem)
              if elem_value.raw.is_a?(Array) || elem_value.raw.is_a?(Hash)
                raise generate_error("#{where}: field '#{spec}' contains a nested #{type_name(elem_value)} — terms must be scalars.")
              end
              s = elem_value.to_string
              s.empty? ? nil : s
            end
          when Hash
            raise generate_error("#{where}: field '#{spec}' is a table — terms must be a scalar or an array of scalars.")
          else
            s = value.to_string
            s.empty? ? [] of String : [s]
          end
        end

        private def template_spec?(spec : String) : Bool
          spec.includes?("{{") || spec.includes?("{%")
        end

        private def render_spec(spec : String, item : Crinja::Value, env : Crinja,
                                template_cache : Hash(String, Crinja::Template),
                                where : String) : String
          template = template_cache[spec] ||= begin
            env.from_string(spec)
          rescue ex : Crinja::Error
            raise generate_error("#{where}: template #{spec.inspect} does not parse: #{ex.message}")
          end
          template.render({"item" => item}).strip
        rescue ex : Crinja::Error
          raise generate_error("#{where}: template #{spec.inspect} failed to render: #{ex.message}")
        end

        # Dotted field lookup on one record. Missing anywhere on the path is
        # a hard error listing the keys that DO exist — the typo-protection
        # half of the field-or-template contract.
        private def lookup_field(item : Crinja::Value, field : String, where : String) : Crinja::Value
          current = item
          field.split('.').each_with_index do |part, i|
            unless current.raw.is_a?(Hash)
              at = i.zero? ? "the record" : "field '#{field.split('.')[0..i - 1].join('.')}'"
              raise generate_error("#{where}: #{at} is #{type_name(current)}, not a table — cannot read '#{part}'.")
            end
            child = current[part]
            if child.raw.is_a?(Crinja::Undefined)
              raise generate_error("#{where}: missing field '#{part}'#{available_keys_hint(current)}.")
            end
            current = child
          end
          current
        end

        private def available_keys_hint(value : Crinja::Value) : String
          raw = value.raw
          return "" unless raw.is_a?(Hash)
          keys = raw.keys.map(&.to_s).sort!
          return "" if keys.empty?
          shown = keys.first(8).join(", ")
          shown += ", …" if keys.size > 8
          " (available: #{shown})"
        end

        private def type_name(value : Crinja::Value) : String
          case raw = value.raw
          when Nil                then "null"
          when Crinja::Undefined  then "undefined"
          when String             then "a string"
          when Crinja::SafeString then "a string"
          when Bool               then "a boolean"
          when Int32, Int64       then "a number"
          when Float64            then "a number"
          when Time               then "a datetime"
          when Array              then "an array"
          when Hash               then "a table"
          else                         raw.class.to_s
          end
        end

        # Compose the synthetic markdown document. TOML front matter between
        # `+++` fences, exactly what `Processor::Markdown.parse` consumes for
        # authored files — one parser, one set of date/taxonomy semantics.
        # All strings go through `FrontmatterWriter.escape_toml_string` (the
        # TOML emission SoT), so a title with quotes or newlines round-trips.
        private def synthetic_markdown(title : String, description : String?,
                                       date_raw : String?,
                                       taxonomies : Hash(String, Array(String)),
                                       body : String) : String
          String.build do |io|
            io << "+++\n"
            io << "title = \"" << Utils::FrontmatterWriter.escape_toml_string(title) << "\"\n"
            if description
              io << "description = \"" << Utils::FrontmatterWriter.escape_toml_string(description) << "\"\n"
            end
            if date_raw
              # Emitted as a TOML STRING, not a datetime literal: the
              # markdown front-matter parser's `parse_time` already accepts
              # every date shape hwaro documents (zone formats first), so a
              # record's raw value gets the same leniency an author gets.
              io << "date = \"" << Utils::FrontmatterWriter.escape_toml_string(date_raw) << "\"\n"
            end
            unless taxonomies.empty?
              io << "\n[taxonomies]\n"
              taxonomies.each do |name, terms|
                io << Utils::FrontmatterWriter.format_toml_key(name) << " = ["
                terms.each_with_index do |term, i|
                  io << ", " unless i.zero?
                  io << '"' << Utils::FrontmatterWriter.escape_toml_string(term) << '"'
                end
                io << "]\n"
              end
            end
            io << "+++\n"
            io << body
            io << '\n' unless body.empty? || body.ends_with?('\n')
          end
        end

        # Convert a source record (Crinja::Value) into `page.extra` shape so
        # templates can read EVERY record field as `page.extra.item.<field>`
        # without the rule having to map each one.
        def item_to_extra(value : Crinja::Value, depth : Int32 = 0) : Models::ExtraValue
          Utils::Nesting.check!(depth)
          case raw = value.raw
          when String             then raw
          when Crinja::SafeString then raw.to_s
          when Bool               then raw
          when Int32              then raw.to_i64
          when Int64              then raw
          when Float64            then raw
          when Time               then Utils::FrontmatterWriter.serialize_time(raw)
          when Array
            raw.map { |elem| item_to_extra(Crinja::Value.new(elem), depth + 1).as(Models::ExtraValue) }
          when Hash
            converted = {} of String => Models::ExtraValue
            raw.each do |k, v|
              converted[k.to_s] = item_to_extra(Crinja::Value.new(v), depth + 1)
            end
            converted
          else
            # Nil, Undefined and exotic runtime values have no ExtraValue
            # shape; render as "" so `page.extra.item.x` is falsy, not a
            # crash.
            ""
          end
        end

        private def generate_error(message : String) : Hwaro::HwaroError
          Hwaro::HwaroError.new(
            code: Hwaro::Errors::HWARO_E_CONTENT,
            message: message,
            hint: "Field values in [[content.generate]] are record field names (dotted for nesting), or Crinja templates over `item` when they contain {{ or {%.",
          )
        end
      end
    end
  end
end
