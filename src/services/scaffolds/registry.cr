# Scaffold registry for managing available scaffolds
#
# Provides a central place to register and retrieve scaffolds
# by their type identifier.

require "./base"
require "./simple"
require "./blog"
require "./docs"

module Hwaro
  module Services
    module Scaffolds
      # Registry for managing scaffold instances
      class Registry
        @@scaffolds = {} of Config::Options::ScaffoldType => Base

        # Register a scaffold instance
        def self.register(scaffold : Base)
          @@scaffolds[scaffold.type] = scaffold
        end

        # Get a scaffold by type
        def self.get(type : Config::Options::ScaffoldType) : Base
          @@scaffolds[type]? || raise ArgumentError.new("Unknown scaffold type: #{type}")
        end

        # Get all registered scaffolds
        def self.all : Array(Base)
          @@scaffolds.values
        end

        # Check if a scaffold type is registered
        def self.has?(type : Config::Options::ScaffoldType) : Bool
          @@scaffolds.has_key?(type)
        end

        # List all available scaffold types with descriptions
        def self.list : Array(Tuple(String, String))
          @@scaffolds.map do |type, scaffold|
            {type.to_s, scaffold.description}
          end
        end

        # Get the default scaffold
        def self.default : Base
          get(Config::Options::ScaffoldType::Simple)
        end
      end

      # Register built-in scaffolds
      Registry.register(Simple.new)
      Registry.register(Blog.new)
      Registry.register(Docs.new)
    end
  end
end
