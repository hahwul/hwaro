# `@/` content-link lookup shared by `tool check-links` and `tool validate`.

require "./content_lister"
require "./generated_content"

module Hwaro
  module Services
    # The `@/` link targets a default `hwaro build` resolves.
    #
    # The build rewrites `href="@/posts/hello.md"` by looking `posts/hello.md`
    # up in its content-path → page map (`InternalLinkResolver.resolve` over
    # `build_pages_by_path`). That lookup is exact: case-sensitive, never
    # percent-decoded, no `./` or `../` normalization, no guessing of an
    # extension or an `_index.md`, and the map only holds pages and sections
    # that survived draft, future and expired filtering. The tools used to
    # test file existence instead, so they passed `@/draft.md`, `@/UPPER.md`
    # (on a case-insensitive filesystem), `@/./x.md`, `@/../README.md` and
    # `@/my%20post.md` — every one a link the build leaves unresolved.
    #
    # The keys come from `ContentLister`, the publish-state source of truth
    # for authored files, plus the planned `[[content.generate]]` pages.
    class InternalLinkIndex
      # The content path an `@/` destination looks up: the part before `#`,
      # then before `?`, split exactly as `InternalLinkResolver` does. nil
      # when `destination` is not an `@/` link.
      def self.key(destination : String) : String?
        return unless destination.starts_with?("@/")
        destination[2..].split('#', 2).first.partition('?')[0]
      end

      @states : Hash(String, String)?

      def initialize(@content_dir : String)
      end

      # nil when a default build resolves `key`. Otherwise why it does not:
      # "empty link", "not found", or the target's publish state ("draft",
      # "future", "expired").
      def unresolved_reason(key : String) : String?
        return "empty link" if key.empty?
        state = states[key]?
        return "not found" unless state
        state == PublishState::Published.label ? nil : state
      end

      # Human wording for an `unresolved_reason`.
      def self.describe(reason : String) : String
        case reason
        when "draft"   then "target is a draft"
        when "future"  then "target is future-dated"
        when "expired" then "target has expired"
        else                reason
        end
      end

      # Content path (relative to the content dir) → publish state label.
      # Built on first use: most runs never meet an `@/` link.
      private def states : Hash(String, String)
        @states ||= begin
          map = {} of String => String
          lister = ContentLister.new(@content_dir, GeneratedContent.infos(@content_dir))
          lister.list_all.each do |info|
            # Generated rows already carry a content-relative path.
            path = info.generated_from ? info.path : Path[info.path].relative_to(@content_dir).to_s
            # An authored file owns its path, as in the build.
            map[path] = info.status if info.generated_from.nil? || !map.has_key?(path)
          end
          map
        end
      end
    end
  end
end
