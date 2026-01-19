module Hwaro
  module Config
    module Options
      # Available scaffold types for project initialization
      enum ScaffoldType
        Simple  # Basic pages (current default)
        Blog    # Blog-focused with posts, archives, tags
        Docs    # Documentation-focused with sidebar, TOC

        def self.from_string(value : String) : ScaffoldType
          case value.downcase
          when "simple"
            Simple
          when "blog"
            Blog
          when "docs"
            Docs
          else
            raise ArgumentError.new("Unknown scaffold type: #{value}. Available types: simple, blog, docs")
          end
        end

        def to_s : String
          case self
          when Simple then "simple"
          when Blog   then "blog"
          when Docs   then "docs"
          else "simple"
          end
        end
      end

      struct InitOptions
        property path : String
        property force : Bool
        property skip_agents_md : Bool
        property skip_sample_content : Bool
        property skip_taxonomies : Bool
        property multilingual_languages : Array(String)
        property scaffold : ScaffoldType

        def initialize(
          @path : String = ".",
          @force : Bool = false,
          @skip_agents_md : Bool = false,
          @skip_sample_content : Bool = false,
          @skip_taxonomies : Bool = false,
          @multilingual_languages : Array(String) = [] of String,
          @scaffold : ScaffoldType = ScaffoldType::Simple,
        )
        end

        # Check if multilingual mode is enabled
        def multilingual? : Bool
          @multilingual_languages.size > 1
        end
      end
    end
  end
end
