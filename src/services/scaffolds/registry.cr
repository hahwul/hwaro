# Scaffold registry for managing available scaffolds
#
# Provides a central place to register and retrieve scaffolds
# by their type identifier.

require "./base"
require "./simple"
require "./bare"
require "./blog"
require "./docs"
require "./book"
require "./remote"

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
      end

      # Register built-in scaffolds
      Registry.register(Simple.new)
      Registry.register(Bare.new)
      Registry.register(Blog.new)
      Registry.register(Docs.new)
      Registry.register(Book.new)
    end
  end
end
