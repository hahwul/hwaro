# Config section — sitemap, robots, llms and feeds.
#
# One file per config.toml table family: the nested config class(es) plus the
# `Config.load_*` loader(s) that read them. To add a section: create a file
# like this one, then add its property + default in config.cr, its loader to
# `SECTION_LOADERS` there, and its TOML snippet to services/config_snippets.cr.
# Parts only reopen Models / Config: no requires, no load-time statements.
module Hwaro
  module Models
    class SitemapConfig
      property enabled : Bool
      property filename : String
      property changefreq : String
      property priority : Float64
      property exclude : Array(String)

      def initialize
        @enabled = false
        @filename = "sitemap.xml"
        @changefreq = "weekly"
        @priority = 0.5
        @exclude = [] of String
      end
    end

    class RobotsRule
      property user_agent : String
      property allow : Array(String)
      property disallow : Array(String)

      def initialize(user_agent : String)
        @user_agent = user_agent
        @allow = [] of String
        @disallow = [] of String
      end
    end

    class RobotsConfig
      property enabled : Bool
      property filename : String
      property rules : Array(RobotsRule)

      def initialize
        @enabled = true
        @filename = "robots.txt"
        @rules = [] of RobotsRule
      end
    end

    class LlmsConfig
      property enabled : Bool
      property filename : String
      property instructions : String
      property full_enabled : Bool
      property full_filename : String

      def initialize
        @enabled = true
        @filename = "llms.txt"
        @instructions = ""
        @full_enabled = false
        @full_filename = "llms-full.txt"
      end
    end

    class FeedConfig
      property enabled : Bool
      property filename : String
      property type : String
      property truncate : Int32
      property limit : Int32
      property sections : Array(String)
      property default_language_only : Bool
      property full_content : Bool

      def initialize
        @enabled = false
        @filename = ""
        @type = "rss"
        @truncate = 0
        @limit = 10
        @sections = [] of String
        @default_language_only = true
        @full_content = true
      end
    end
  end
end

module Hwaro
  module Models
    class Config
      private def self.load_sitemap(config : Config)
        # Handle backward compatibility where sitemap was just a boolean
        if sitemap_bool = config.raw["sitemap"]?.try(&.as_bool?)
          config.sitemap.enabled = sitemap_bool
        elsif s = config.raw["sitemap"]?.try(&.as_h?)
          config.sitemap.enabled = bool_value(s["enabled"]?, config.sitemap.enabled)
          config.sitemap.filename = s["filename"]?.try(&.as_s?) || config.sitemap.filename
          validate_output_filename!("sitemap", "filename", config.sitemap.filename, "sitemap.xml", allow_empty: false)
          config.sitemap.changefreq = s["changefreq"]?.try(&.as_s?) || config.sitemap.changefreq
          # Keep the priority raw here (NOT clamped) so `hwaro doctor` can detect
          # an out-of-range value and warn/offer a fix. The sitemap EMITTER
          # (sitemap.cr) clamps to [0.0, 1.0] so the generated XML stays valid
          # even for users who never run doctor. NaN is the exception: it
          # sails through both doctor's range checks and the emitter's clamp
          # (NaN comparisons are all false) and lands in the XML as "NaN",
          # so non-finite values fall back to the default here.
          pr = float_value(s["priority"]?, config.sitemap.priority)
          config.sitemap.priority = pr.finite? ? pr : config.sitemap.priority
          if exclude_arr = s["exclude"]?.try(&.as_a?)
            config.sitemap.exclude = exclude_arr.compact_map(&.as_s?)
          end
        end
      end

      private def self.load_robots(config : Config)
        return unless s = config.raw["robots"]?.try(&.as_h?)

        config.robots.enabled = bool_value(s["enabled"]?, config.robots.enabled)
        config.robots.filename = s["filename"]?.try(&.as_s?) || config.robots.filename
        validate_output_filename!("robots", "filename", config.robots.filename, "robots.txt", allow_empty: false)

        if rules = s["rules"]?.try(&.as_a?)
          config.robots.rules = rules.compact_map do |rule_any|
            if rule_h = rule_any.as_h?
              user_agent = rule_h["user_agent"]?.try(&.as_s?) || "*"
              rule = RobotsRule.new(user_agent)
              rule.allow = string_or_array(rule_h["allow"]?)
              rule.disallow = string_or_array(rule_h["disallow"]?)
              rule
            end
          end
        end
      end

      private def self.load_llms(config : Config)
        return unless s = config.raw["llms"]?.try(&.as_h?)

        config.llms.enabled = bool_value(s["enabled"]?, config.llms.enabled)
        config.llms.filename = s["filename"]?.try(&.as_s?) || config.llms.filename
        config.llms.instructions = s["instructions"]?.try(&.as_s?) || config.llms.instructions
        config.llms.full_enabled = bool_value(s["full_enabled"]?, config.llms.full_enabled)
        config.llms.full_filename = s["full_filename"]?.try(&.as_s?) || config.llms.full_filename
        # Empty stays legal here: llms.cr already substitutes llms.txt /
        # llms-full.txt for an empty value, so those configs build today.
        validate_output_filename!("llms", "filename", config.llms.filename, "llms.txt", allow_empty: true)
        validate_output_filename!("llms", "full_filename", config.llms.full_filename, "llms-full.txt", allow_empty: true)
      end

      private def self.load_feeds(config : Config)
        return unless s = config.raw["feeds"]?.try(&.as_h?)

        # Backward compatibility for 'generate' property
        enabled = s["enabled"]?.try(&.as_bool?)
        generate = s["generate"]?.try(&.as_bool?)

        if !enabled.nil?
          config.feeds.enabled = enabled
        elsif !generate.nil?
          config.feeds.enabled = generate
        end

        config.feeds.filename = s["filename"]?.try(&.as_s?) || config.feeds.filename
        # Empty is the shipped default (safe_feed_filename derives rss.xml /
        # atom.xml from `type`), so only non-file values are rejected.
        validate_output_filename!("feeds", "filename", config.feeds.filename, "rss.xml", allow_empty: true)
        config.feeds.type = s["type"]?.try(&.as_s?) || config.feeds.type
        config.feeds.truncate = int_value(s["truncate"]?, config.feeds.truncate)
        config.feeds.limit = int_value(s["limit"]?, config.feeds.limit)
        if sections = s["sections"]?.try(&.as_a?)
          config.feeds.sections = sections.compact_map(&.as_s?)
        end
        config.feeds.default_language_only = bool_value(s["default_language_only"]?, config.feeds.default_language_only)
        config.feeds.full_content = bool_value(s["full_content"]?, config.feeds.full_content)
      end
    end
  end
end
