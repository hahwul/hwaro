require "toml"

module Hwaro
  module Schemas
    class FeedConfig
      property generate : Bool
      property filename : String
      property type : String
      property truncate : Int32

      def initialize
        @generate = false
        @filename = ""
        @type = "rss"
        @truncate = 0
      end
    end

    class Config
      property title : String
      property description : String
      property base_url : String
      property sitemap : Bool
      property feeds : FeedConfig
      property raw : Hash(String, TOML::Any)

      def initialize
        @title = "Hwaro Site"
        @description = ""
        @base_url = ""
        @sitemap = false
        @feeds = FeedConfig.new
        @raw = Hash(String, TOML::Any).new
      end

      def self.load(config_path : String = "config.toml") : Config
        config = new
        if File.exists?(config_path)
          config.raw = TOML.parse_file(config_path)
          config.title = config.raw["title"]?.try(&.as_s) || config.title
          config.description = config.raw["description"]?.try(&.as_s) || config.description
          config.base_url = config.raw["base_url"]?.try(&.as_s) || config.base_url
          config.sitemap = config.raw["sitemap"]?.try(&.as_bool) || config.sitemap

          # Load feeds configuration
          if feeds_section = config.raw["feeds"]?.try(&.as_h)
            config.feeds.generate = feeds_section["generate"]?.try(&.as_bool) || config.feeds.generate
            config.feeds.filename = feeds_section["filename"]?.try(&.as_s) || config.feeds.filename
            config.feeds.type = feeds_section["type"]?.try(&.as_s) || config.feeds.type
            config.feeds.truncate = feeds_section["truncate"]?.try(&.as_i) || config.feeds.truncate
          end
        end
        config
      end
    end
  end
end
