# Base processor interface for content processing plugins
#
# This abstract class provides a common interface for all processors.
# To create a new processor, inherit from this class and implement
# the required methods.
#
# Example:
#   class MyProcessor < Hwaro::Content::Processors::Base
#     def name : String
#       "my-processor"
#     end
#
#     def process(content : String, context : ProcessorContext) : String
#       # Transform content
#       content.upcase
#     end
#   end

module Hwaro
  module Content
    module Processors
      # Context passed to processors with relevant metadata
      struct ProcessorContext
        property file_path : String
        property output_path : String
        property config : Hash(String, String)

        def initialize(
          @file_path : String = "",
          @output_path : String = "",
          @config : Hash(String, String) = {} of String => String,
        )
        end
      end

      # Result from processor operations
      struct ProcessorResult
        property content : String
        property metadata : Hash(String, String)
        property success : Bool
        property error : String?

        def initialize(
          @content : String,
          @success : Bool = true,
          @metadata : Hash(String, String) = {} of String => String,
          @error : String? = nil,
        )
        end

        def self.error(message : String) : ProcessorResult
          new(content: "", success: false, error: message)
        end
      end

      # Abstract base class for all content processors
      abstract class Base
        # Returns the unique name identifier for this processor
        abstract def name : String

        # Returns file extensions this processor can handle
        abstract def extensions : Array(String)

        # Process content and return transformed result
        abstract def process(content : String, context : ProcessorContext) : ProcessorResult

        # Check if this processor can handle the given file
        def can_process?(file_path : String) : Bool
          ext = File.extname(file_path).downcase
          extensions.includes?(ext)
        end

        # Priority for processor ordering (higher = runs first)
        def priority : Int32
          0
        end
      end

      # Registry for managing processor instances
      class Registry
        @@processors = {} of String => Base
        @@sorted_processors : Array(Base)? = nil

        # Register a processor instance
        def self.register(processor : Base)
          @@processors[processor.name] = processor
          @@sorted_processors = nil # Invalidate cache
        end

        # Get a processor by name
        def self.get(name : String) : Base?
          @@processors[name]?
        end

        # Get all registered processors (cached and sorted by priority)
        def self.all : Array(Base)
          @@sorted_processors ||= @@processors.values.sort_by(&.priority).reverse
        end

        # Get processors that can handle a specific file
        def self.for_file(file_path : String) : Array(Base)
          all.select(&.can_process?(file_path))
        end

        # Clear all registered processors
        def self.clear
          @@processors.clear
          @@sorted_processors = nil
        end

        # Check if a processor is registered
        def self.has?(name : String) : Bool
          @@processors.has_key?(name)
        end

        # List all registered processor names
        def self.names : Array(String)
          @@processors.keys
        end
      end
    end
  end
end
