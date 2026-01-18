require "toml"

module Hwaro
  module Models
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

    class SearchConfig
      property enabled : Bool
      property format : String
      property fields : Array(String)
      property filename : String

      def initialize
        @enabled = false
        @format = "fuse_json"
        @fields = ["title", "content"]
        @filename = "search.json"
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

    # Plugin configuration for extensibility
    class PluginConfig
      property processors : Array(String)

      def initialize
        @processors = ["markdown"]  # Default processor
      end
    end

    # Pagination configuration
    class PaginationConfig
      property enabled : Bool
      property per_page : Int32

      def initialize
        @enabled = false
        @per_page = 10
      end
    end

    class Config
      property title : String
      property description : String
      property base_url : String
      property sitemap : SitemapConfig
      property robots : RobotsConfig
      property llms : LlmsConfig
      property feeds : FeedConfig
      property search : SearchConfig
      property plugins : PluginConfig
      property pagination : PaginationConfig
      property raw : Hash(String, TOML::Any)

      def initialize
        @title = "Hwaro Site"
        @description = ""
        @base_url = ""
        @sitemap = SitemapConfig.new
        @robots = RobotsConfig.new
        @llms = LlmsConfig.new
        @feeds = FeedConfig.new
        @search = SearchConfig.new
        @plugins = PluginConfig.new
        @pagination = PaginationConfig.new
        @raw = Hash(String, TOML::Any).new
      end

      def self.load(config_path : String = "config.toml") : Config
        config = new
        if File.exists?(config_path)
          config.raw = TOML.parse_file(config_path)
          config.title = config.raw["title"]?.try(&.as_s?) || config.title
          config.description = config.raw["description"]?.try(&.as_s?) || config.description
          config.base_url = config.raw["base_url"]?.try(&.as_s?) || config.base_url

          # Load Sitemap configuration
          # Handle backward compatibility where sitemap was just a boolean
          if sitemap_bool = config.raw["sitemap"]?.try(&.as_bool?)
            config.sitemap.enabled = sitemap_bool
          elsif sitemap_section = config.raw["sitemap"]?.try(&.as_h?)
            config.sitemap.enabled = sitemap_section["enabled"]?.try(&.as_bool?) || config.sitemap.enabled
            config.sitemap.filename = sitemap_section["filename"]?.try(&.as_s?) || config.sitemap.filename
            config.sitemap.changefreq = sitemap_section["changefreq"]?.try(&.as_s?) || config.sitemap.changefreq
            config.sitemap.priority = sitemap_section["priority"]?.try { |v| v.as_f? || v.as_i?.try(&.to_f) } || config.sitemap.priority
          end

          # Load Robots configuration
          if robots_section = config.raw["robots"]?.try(&.as_h?)
            config.robots.enabled = robots_section["enabled"]?.try(&.as_bool?) || config.robots.enabled
            config.robots.filename = robots_section["filename"]?.try(&.as_s?) || config.robots.filename

            if rules = robots_section["rules"]?.try(&.as_a?)
              config.robots.rules = rules.compact_map do |rule_any|
                if rule_h = rule_any.as_h?
                  user_agent = rule_h["user_agent"]?.try(&.as_s?) || "*"
                  rule = RobotsRule.new(user_agent)

                  if allow = rule_h["allow"]?
                    if allow_arr = allow.as_a?
                      rule.allow = allow_arr.compact_map(&.as_s?)
                    elsif allow_str = allow.as_s?
                      rule.allow = [allow_str]
                    end
                  end

                  if disallow = rule_h["disallow"]?
                    if disallow_arr = disallow.as_a?
                      rule.disallow = disallow_arr.compact_map(&.as_s?)
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

          # Load LLMs configuration
          if llms_section = config.raw["llms"]?.try(&.as_h?)
            config.llms.enabled = llms_section["enabled"]?.try(&.as_bool?) || config.llms.enabled
            config.llms.filename = llms_section["filename"]?.try(&.as_s?) || config.llms.filename
            config.llms.instructions = llms_section["instructions"]?.try(&.as_s?) || config.llms.instructions
          end

          # Load Feeds configuration
          if feeds_section = config.raw["feeds"]?.try(&.as_h?)
            # Backward compatibility for 'generate' property
            enabled = feeds_section["enabled"]?.try(&.as_bool?)
            generate = feeds_section["generate"]?.try(&.as_bool?)

            if !enabled.nil?
              config.feeds.enabled = enabled
            elsif !generate.nil?
              config.feeds.enabled = generate
            end

            config.feeds.filename = feeds_section["filename"]?.try(&.as_s?) || config.feeds.filename
            config.feeds.type = feeds_section["type"]?.try(&.as_s?) || config.feeds.type
            config.feeds.truncate = feeds_section["truncate"]?.try { |v| v.as_i? || v.as_f?.try(&.to_i) } || config.feeds.truncate
            config.feeds.limit = feeds_section["limit"]?.try { |v| v.as_i? || v.as_f?.try(&.to_i) } || config.feeds.limit
            if sections = feeds_section["sections"]?.try(&.as_a?)
              config.feeds.sections = sections.compact_map(&.as_s?)
            end
          end

          # Load search configuration
          if search_section = config.raw["search"]?.try(&.as_h?)
            config.search.enabled = search_section["enabled"]?.try(&.as_bool?) || config.search.enabled
            config.search.format = search_section["format"]?.try(&.as_s?) || config.search.format
            config.search.filename = search_section["filename"]?.try(&.as_s?) || config.search.filename
            if fields = search_section["fields"]?.try(&.as_a?)
              config.search.fields = fields.compact_map(&.as_s?)
            end
          end

          # Load plugins configuration
          if plugins_section = config.raw["plugins"]?.try(&.as_h?)
            if processors = plugins_section["processors"]?.try(&.as_a?)
              config.plugins.processors = processors.compact_map(&.as_s?)
            end
          end

          # Load pagination configuration
          if pagination_section = config.raw["pagination"]?.try(&.as_h?)
            config.pagination.enabled = pagination_section["enabled"]?.try(&.as_bool?) || config.pagination.enabled
            config.pagination.per_page = pagination_section["per_page"]?.try { |v| v.as_i? || v.as_f?.try(&.to_i) } || config.pagination.per_page
          end
        end
        config
      end
    end
  end
end
