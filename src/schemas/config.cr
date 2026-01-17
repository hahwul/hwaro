require "toml"

module Hwaro
  module Schemas
    class Config
      property title : String
      property description : String
      property base_url : String
      property raw : Hash(String, TOML::Any)

      def initialize
        @title = "Hwaro Site"
        @description = ""
        @base_url = ""
        @raw = Hash(String, TOML::Any).new
      end

      def self.load(config_path : String = "config.toml") : Config
        config = new
        if File.exists?(config_path)
          config.raw = TOML.parse_file(config_path)
          config.title = config.raw["title"]?.try(&.as_s) || config.title
          config.description = config.raw["description"]?.try(&.as_s) || config.description
          config.base_url = config.raw["base_url"]?.try(&.as_s) || config.base_url
        end
        config
      end
    end
  end
end
