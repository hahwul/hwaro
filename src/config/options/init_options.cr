module Hwaro
  module Config
    module Options
      # Available scaffold types for project initialization
      enum ScaffoldType
        Simple   # Basic pages (current default)
        Blog     # Blog-focused with posts, archives, tags
        Docs     # Documentation-focused with sidebar, TOC
        BlogDark # Blog-focused with dark theme
        DocsDark # Documentation-focused with dark theme

        def self.from_string(value : String) : ScaffoldType
          case value.downcase
          when "simple"
            Simple
          when "blog"
            Blog
          when "docs"
            Docs
          when "blog-dark"
            BlogDark
          when "docs-dark"
            DocsDark
          else
            raise ArgumentError.new("Unknown scaffold type: #{value}. Available types: simple, blog, blog-dark, docs, docs-dark")
          end
        end

        def to_s : String
          case self
          when Simple   then "simple"
          when Blog     then "blog"
          when Docs     then "docs"
          when BlogDark then "blog-dark"
          when DocsDark then "docs-dark"
          else               "simple"
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
        property scaffold_remote : String?

        def initialize(
          @path : String = ".",
          @force : Bool = false,
          @skip_agents_md : Bool = false,
          @skip_sample_content : Bool = false,
          @skip_taxonomies : Bool = false,
          @multilingual_languages : Array(String) = [] of String,
          @scaffold : ScaffoldType = ScaffoldType::Simple,
          @scaffold_remote : String? = nil,
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
