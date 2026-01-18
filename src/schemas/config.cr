require "toml"

module Hwaro
  module Schemas
    class SitemapConfig
      property enabled : Bool
      property filename : String
      property changefreq : String
      property priority : Float64

      def initialize
        @enabled = false
        @filename = "sitemap.xml"
        @changefreq = "weekly"
        @priority = 0.5
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

      def initialize
        @enabled = true
        @filename = "llms.txt"
        @instructions = ""
      end
    end

    class FeedConfig
      property enabled : Bool
      property filename : String
      property type : String
      property truncate : Int32
      property limit : Int32
      property sections : Array(String)

      def initialize
        @enabled = false
        @filename = ""
        @type = "rss"
        @truncate = 0
        @limit = 10
        @sections = [] of String
      end
    end

    class SeoConfig
      property sitemap : SitemapConfig
      property robots : RobotsConfig
      property llms : LlmsConfig
      property feeds : FeedConfig

      def initialize
        @sitemap = SitemapConfig.new
        @robots = RobotsConfig.new
        @llms = LlmsConfig.new
        @feeds = FeedConfig.new
      end
    end

    # Plugin configuration for extensibility
    class PluginConfig
      property processors : Array(String)

      def initialize
        @processors = ["markdown"]  # Default processor
      end
    end

    class Config
      property title : String
      property description : String
      property base_url : String
      property seo : SeoConfig
      property plugins : PluginConfig
      property raw : Hash(String, TOML::Any)

      def initialize
        @title = "Hwaro Site"
        @description = ""
        @base_url = ""
        @seo = SeoConfig.new
        @plugins = PluginConfig.new
        @raw = Hash(String, TOML::Any).new
      end

      def self.load(config_path : String = "config.toml") : Config
        config = new
        if File.exists?(config_path)
          config.raw = TOML.parse_file(config_path)
          config.title = config.raw["title"]?.try(&.as_s) || config.title
          config.description = config.raw["description"]?.try(&.as_s) || config.description
          config.base_url = config.raw["base_url"]?.try(&.as_s) || config.base_url

          # Backward compatibility for sitemap
          if sitemap_bool = config.raw["sitemap"]?.try(&.as_bool)
             config.seo.sitemap.enabled = sitemap_bool
          end

           # Backward compatibility for feeds
          if feeds_section = config.raw["feeds"]?.try(&.as_h)
            config.seo.feeds.enabled = feeds_section["generate"]?.try(&.as_bool) || config.seo.feeds.enabled
            config.seo.feeds.filename = feeds_section["filename"]?.try(&.as_s) || config.seo.feeds.filename
            config.seo.feeds.type = feeds_section["type"]?.try(&.as_s) || config.seo.feeds.type
            config.seo.feeds.truncate = feeds_section["truncate"]?.try { |v| v.as_i? || v.as_f?.try(&.to_i) } || config.seo.feeds.truncate
          end

          # Load new SEO configuration
          if seo_section = config.raw["seo"]?.try(&.as_h)
            # Sitemap
            if sitemap_section = seo_section["sitemap"]?.try(&.as_h)
              config.seo.sitemap.enabled = sitemap_section["enabled"]?.try(&.as_bool) || config.seo.sitemap.enabled
              config.seo.sitemap.filename = sitemap_section["filename"]?.try(&.as_s) || config.seo.sitemap.filename
              config.seo.sitemap.changefreq = sitemap_section["changefreq"]?.try(&.as_s) || config.seo.sitemap.changefreq
              config.seo.sitemap.priority = sitemap_section["priority"]?.try { |v| v.as_f? || v.as_i?.try(&.to_f) } || config.seo.sitemap.priority
            end

            # Robots
            if robots_section = seo_section["robots"]?.try(&.as_h)
              config.seo.robots.enabled = robots_section["enabled"]?.try(&.as_bool) || config.seo.robots.enabled
              config.seo.robots.filename = robots_section["filename"]?.try(&.as_s) || config.seo.robots.filename

              if rules = robots_section["rules"]?.try(&.as_a)
                config.seo.robots.rules = rules.compact_map do |rule_any|
                  if rule_h = rule_any.as_h?
                    user_agent = rule_h["user_agent"]?.try(&.as_s) || "*"
                    rule = RobotsRule.new(user_agent)

                    if allow = rule_h["allow"]?
                      if allow_arr = allow.as_a?
                        rule.allow = allow_arr.map(&.as_s)
                      elsif allow_str = allow.as_s?
                        rule.allow = [allow_str]
                      end
                    end

                    if disallow = rule_h["disallow"]?
                      if disallow_arr = disallow.as_a?
                        rule.disallow = disallow_arr.map(&.as_s)
                      elsif disallow_str = disallow.as_s?
                        rule.disallow = [disallow_str]
                      end
                    end
                    rule
                  else
                    nil
                  end
                end
              end
            end

            # LLMs
            if llms_section = seo_section["llms"]?.try(&.as_h)
              config.seo.llms.enabled = llms_section["enabled"]?.try(&.as_bool) || config.seo.llms.enabled
              config.seo.llms.filename = llms_section["filename"]?.try(&.as_s) || config.seo.llms.filename
              config.seo.llms.instructions = llms_section["instructions"]?.try(&.as_s) || config.seo.llms.instructions
            end

            # Feeds
            if feeds_section = seo_section["feeds"]?.try(&.as_h)
              config.seo.feeds.enabled = feeds_section["enabled"]?.try(&.as_bool) || config.seo.feeds.enabled
              config.seo.feeds.filename = feeds_section["filename"]?.try(&.as_s) || config.seo.feeds.filename
              config.seo.feeds.type = feeds_section["type"]?.try(&.as_s) || config.seo.feeds.type
              config.seo.feeds.truncate = feeds_section["truncate"]?.try { |v| v.as_i? || v.as_f?.try(&.to_i) } || config.seo.feeds.truncate
              config.seo.feeds.limit = feeds_section["limit"]?.try { |v| v.as_i? || v.as_f?.try(&.to_i) } || config.seo.feeds.limit
              if sections = feeds_section["sections"]?.try(&.as_a)
                config.seo.feeds.sections = sections.map(&.as_s)
              end
            end
          end

          # Load plugins configuration
          if plugins_section = config.raw["plugins"]?.try(&.as_h)
            if processors = plugins_section["processors"]?.try(&.as_a)
              config.plugins.processors = processors.map(&.as_s)
            end
          end
        end
        config
      end
    end
  end
end
