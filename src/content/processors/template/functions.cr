require "crinja"
require "json"
require "yaml"
require "toml"

module Hwaro::Content::Processors::Template
  module Functions
    extend self

    def register(engine : Crinja)
      # now() function - returns current time
      engine.functions["now"] = Crinja.function({format: nil}) do
        format = arguments["format"]
        time = Time.local

        if format.none?
          Crinja::Value.new(time.to_s("%Y-%m-%d %H:%M:%S"))
        else
          Crinja::Value.new(time.to_s(format.to_s))
        end
      end

      # url_for() function - generate URL for a path
      engine.functions["url_for"] = Crinja.function({path: ""}) do
        path = arguments["path"].to_s
        base_url = env.resolve("base_url").to_s

        if path.starts_with?("/")
          Crinja::Value.new(base_url.rstrip("/") + path)
        else
          Crinja::Value.new(base_url.rstrip("/") + "/" + path)
        end
      end

      # get_url() function - alias for url_for to match
      engine.functions["get_url"] = engine.functions["url_for"]

      # get_page() function - get page data by path
      # Usage: {% set about = get_page(path="about.md") %}
      #        {{ about.title }}
      engine.functions["get_page"] = Crinja.function({path: ""}) do
        path_arg = arguments["path"].to_s

        # Optimised O(1) lookup
        pages_map = env.resolve("__pages_by_path__")
        if !pages_map.raw.nil? && pages_map.raw.is_a?(Hash)
          raw_map = pages_map.raw.as(Hash)
          if found = raw_map[path_arg]?
            return found
          elsif found = raw_map["/#{path_arg.chomp(".md")}/"]?
            return found
          end
          # If map is present but page not found, return nil (miss)
          # This avoids falling back to linear search on miss when we have the index.
          return Crinja::Value.new(nil)
        end

        # Fallback to linear search O(N) if map is not available
        pages_val = env.resolve("__all_pages__")
        result = Crinja::Value.new(nil)

        raw_pages = pages_val.raw
        if raw_pages.is_a?(Array)
          raw_pages.each do |page_val|
            # Handle Crinja::Value wrapping a Hash
            raw_page = page_val.raw
            if raw_page.is_a?(Hash)
              page_path = raw_page["path"]?.try(&.to_s) || ""
              page_url = raw_page["url"]?.try(&.to_s) || ""

              if page_path == path_arg || page_url == path_arg || page_url == "/#{path_arg.chomp(".md")}/"
                result = page_val
                break
              end
            end
          end
        end

        result
      end

      # get_section() function - get section data by path
      # Usage: {% set blog = get_section(path="blog/_index.md") %}
      #        {% for page in blog.pages %}
      engine.functions["get_section"] = Crinja.function({path: ""}) do
        path_arg = arguments["path"].to_s
        sections_val = env.resolve("__all_sections__")

        result = Crinja::Value.new(nil)

        raw_sections = sections_val.raw
        if raw_sections.is_a?(Array)
          raw_sections.each do |section_val|
            if section_val.is_a?(Hash)
              section_path = section_val["path"]?.try(&.to_s) || ""
              section_name = section_val["name"]?.try(&.to_s) || ""
              section_url = section_val["url"]?.try(&.to_s) || ""

              # Match by path, name, or URL
              if section_path == path_arg || section_name == path_arg || section_url == "/#{path_arg}/"
                result = Crinja::Value.new(section_val)
                break
              end
            end
          end
        end

        result
      end

      # get_taxonomy() function - get taxonomy terms and their pages
      # Usage: {% set tags = get_taxonomy(kind="tags") %}
      #        {% for term in tags.items %}
      engine.functions["get_taxonomy"] = Crinja.function({kind: ""}) do
        kind = arguments["kind"].to_s
        taxonomies_val = env.resolve("__taxonomies__")

        result = Crinja::Value.new(nil)

        raw_taxonomies = taxonomies_val.raw
        if raw_taxonomies.is_a?(Hash)
          if taxonomy_val = raw_taxonomies[kind]?
            result = Crinja::Value.new(taxonomy_val)
          end
        end

        result
      end

      # get_taxonomy_url() function - get URL for a taxonomy term
      # Usage: {{ get_taxonomy_url(kind="tags", term="crystal") }}
      engine.functions["get_taxonomy_url"] = Crinja.function({kind: "", term: ""}) do
        kind = arguments["kind"].to_s
        term = arguments["term"].to_s
        base_url = env.resolve("base_url").to_s

        # Generate slug from term
        slug = term.downcase
          .gsub(/[^\w\s-]/, "")
          .gsub(/[\s_-]+/, "-")
          .strip("-")

        url = "/#{kind}/#{slug}/"
        Crinja::Value.new(base_url.rstrip("/") + url)
      end

      # resize_image() function - placeholder for image resizing
      # Usage: {{ resize_image(path="/images/photo.jpg", width=800, height=600) }}
      # Note: This is a placeholder - actual image processing would need additional libraries
      engine.functions["resize_image"] = Crinja.function({path: "", width: 0, height: 0, op: "fill"}) do
        path = arguments["path"].to_s
        width = arguments["width"].as_number.to_i
        height = arguments["height"].as_number.to_i
        op = arguments["op"].to_s

        # Resolve URL
        base_url = env.resolve("base_url").to_s
        final_url = if path.starts_with?("/")
                      base_url.rstrip("/") + path
                    else
                      base_url.rstrip("/") + "/" + path
                    end

        # For now, just return the original path (resolved)
        # TODO: Implement actual image resizing with an image processing library
        Crinja::Value.new({
          "url"    => Crinja::Value.new(final_url),
          "width"  => Crinja::Value.new(width),
          "height" => Crinja::Value.new(height),
        })
      end

      # load_data() function - load data from JSON/TOML/YAML files
      # Usage: {% set data = load_data(path="data/menu.json") %}
      engine.functions["load_data"] = Crinja.function({path: ""}) do
        path = arguments["path"].to_s

        result = Crinja::Value.new(nil)

        begin
          if File.exists?(path)
            content = File.read(path)

            if path.ends_with?(".json")
              # Parse JSON
              json_data = JSON.parse(content)
              result = Functions.json_to_crinja(json_data)
            elsif path.ends_with?(".toml")
              # Parse TOML
              toml_data = TOML.parse(content)
              result = Functions.toml_to_crinja(toml_data)
            elsif path.ends_with?(".yaml") || path.ends_with?(".yml")
              # Parse YAML
              yaml_data = YAML.parse(content)
              result = Functions.yaml_to_crinja(yaml_data)
            elsif path.ends_with?(".csv")
              # Parse CSV as array of arrays
              lines = content.split("\n").reject(&.empty?)
              csv_data = lines.map do |line|
                Crinja::Value.new(line.split(",").map { |cell| Crinja::Value.new(cell.strip) })
              end
              result = Crinja::Value.new(csv_data)
            end
          end
        rescue ex
          # Return nil on error
          result = Crinja::Value.new(nil)
        end

        result
      end
    end

    # Helper to convert JSON to Crinja value
    def json_to_crinja(json : JSON::Any) : Crinja::Value
      case json.raw
      when Hash
        hash = {} of String => Crinja::Value
        json.as_h.each { |k, v| hash[k] = json_to_crinja(v) }
        Crinja::Value.new(hash)
      when Array
        arr = json.as_a.map { |v| json_to_crinja(v) }
        Crinja::Value.new(arr)
      when String
        Crinja::Value.new(json.as_s)
      when Int64
        Crinja::Value.new(json.as_i64)
      when Float64
        Crinja::Value.new(json.as_f)
      when Bool
        Crinja::Value.new(json.as_bool)
      when Nil
        Crinja::Value.new(nil)
      else
        Crinja::Value.new(json.to_s)
      end
    end

    # Helper to convert TOML to Crinja value
    def toml_to_crinja(toml : TOML::Table) : Crinja::Value
      hash = {} of String => Crinja::Value
      toml.each do |k, v|
        hash[k] = toml_any_to_crinja(v)
      end
      Crinja::Value.new(hash)
    end

    def toml_any_to_crinja(value : TOML::Any) : Crinja::Value
      if str = value.as_s?
        Crinja::Value.new(str)
      elsif int = value.as_i?
        Crinja::Value.new(int.to_i64)
      elsif float = value.as_f?
        Crinja::Value.new(float)
      elsif bool = value.as_bool?
        Crinja::Value.new(bool)
      elsif arr = value.as_a?
        Crinja::Value.new(arr.map { |v| toml_any_to_crinja(v) })
      elsif hash = value.as_h?
        h = {} of String => Crinja::Value
        hash.each { |k, v| h[k] = toml_any_to_crinja(v) }
        Crinja::Value.new(h)
      else
        Crinja::Value.new(value.to_s)
      end
    end

    # Helper to convert YAML to Crinja value
    def yaml_to_crinja(yaml : YAML::Any) : Crinja::Value
      case yaml.raw
      when Hash
        hash = {} of String => Crinja::Value
        yaml.as_h.each { |k, v| hash[k.to_s] = yaml_to_crinja(v) }
        Crinja::Value.new(hash)
      when Array
        arr = yaml.as_a.map { |v| yaml_to_crinja(v) }
        Crinja::Value.new(arr)
      when String
        Crinja::Value.new(yaml.as_s)
      when Int64
        Crinja::Value.new(yaml.as_i64)
      when Float64
        Crinja::Value.new(yaml.as_f)
      when Bool
        Crinja::Value.new(yaml.as_bool)
      when Nil
        Crinja::Value.new(nil)
      else
        Crinja::Value.new(yaml.to_s)
      end
    end
  end
end
