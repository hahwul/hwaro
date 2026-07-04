require "crinja"

module Hwaro
  module Content
    module Processors
      module Filters
        module MenuFilters
          def self.register(env : Crinja)
            # `active_path` — is this menu entry's `url` the current page's
            # own URL, or (with `ancestor=true`) an ANCESTOR of it? Lets a
            # nav template flag the active item without hardcoding
            # per-scaffold URL comparisons:
            #   {% if item.url | active_path %}aria-current="page"{% endif %}
            #   {% if item.url | active_path(ancestor=true) %}class="open"{% endif %}
            #
            # An external entry (`http://`, `https://`, `//`) is never
            # active — `page_url` (see `build_template_variables` in
            # render.cr) is always an internal, root-relative URL. Both
            # sides are normalized to exactly one trailing slash before
            # comparing, so `/posts` and `/posts/` compare equal. The root
            # path (`/`) only ever matches exactly, even under
            # `ancestor=true` — otherwise every page on the site would show
            # the home nav item as active/open.
            env.filters["active_path"] = Crinja.filter({ancestor: false}) do
              value = target.to_s

              if external_url?(value)
                false
              else
                ancestor = arguments["ancestor"].truthy?
                current = normalize_path(env.resolve("page_url").to_s)
                entry_path = normalize_path(value)

                if entry_path == "/"
                  current == "/"
                elsif ancestor
                  current.starts_with?(entry_path)
                else
                  current == entry_path
                end
              end
            end
          end

          private def self.external_url?(url : String) : Bool
            url.starts_with?("http://") || url.starts_with?("https://") || url.starts_with?("//")
          end

          # Canonicalizes a root-relative path to exactly one leading and
          # one trailing slash, so equivalent forms (`posts`, `/posts`,
          # `/posts/`) compare equal.
          private def self.normalize_path(path : String) : String
            path = "/#{path}" unless path.starts_with?("/")
            "#{path.rstrip("/")}/"
          end
        end
      end
    end
  end
end
