module Hwaro
  module Config
    module Options
      # Available scaffold types for project initialization
      enum ScaffoldType
        Simple   # Basic pages (current default)
        Bare     # Minimal structure with semantic HTML only
        Blog     # Blog-focused with posts, archives, tags
        Docs     # Documentation-focused with sidebar, TOC
        BlogDark # Blog-focused with dark theme
        DocsDark # Documentation-focused with dark theme
        Book     # Book-focused with chapters, like mdBook
        BookDark # Book-focused with dark theme

        def self.from_string(value : String) : ScaffoldType
          case value.downcase
          when "simple"
            Simple
          when "bare"
            Bare
          when "blog"
            Blog
          when "docs"
            Docs
          when "blog-dark"
            BlogDark
          when "docs-dark"
            DocsDark
          when "book"
            Book
          when "book-dark"
            BookDark
          else
            raise ArgumentError.new("Unknown scaffold type: #{value}. Available types: simple, bare, blog, blog-dark, docs, docs-dark, book, book-dark")
          end
        end

        def to_s : String
          case self
          when Simple   then "simple"
          when Bare     then "bare"
          when Blog     then "blog"
          when Docs     then "docs"
          when BlogDark then "blog-dark"
          when DocsDark then "docs-dark"
          when Book     then "book"
          when BookDark then "book-dark"
          else               "simple"
          end
        end
      end

      # AGENTS.md content mode
      enum AgentsMode
        Remote # Lightweight with links to online docs (default)
        Local  # Full embedded reference for offline use

        def self.from_string(value : String) : AgentsMode
          case value.downcase
          when "remote"
            Remote
          when "local"
            Local
          else
            raise ArgumentError.new("Unknown agents mode: #{value}. Available modes: remote, local")
          end
        end

        def to_s : String
          case self
          when Remote then "remote"
          when Local  then "local"
          else             "remote"
          end
        end
      end

      struct InitOptions
        # BCP 47 subset: primary subtag (2-3 letters) plus optional
        # script/region subtags (2-8 alphanumerics each). Covers "en",
        # "pt-BR", "zh-Hant", "zh-Hant-TW".
        LANGUAGE_CODE_REGEX = /\A[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*\z/

        def self.validate_language_code!(code : String) : Nil
          unless LANGUAGE_CODE_REGEX.matches?(code)
            raise ArgumentError.new(
              "Invalid language code: '#{code}'. " \
              "Use BCP 47 codes like 'en', 'ko', 'pt-BR', 'zh-Hant'."
            )
          end
        end

        property path : String
        property force : Bool
        property clean : Bool
        property skip_agents_md : Bool
        property skip_sample_content : Bool
        property skip_taxonomies : Bool
        property multilingual_languages : Array(String)
        property scaffold : ScaffoldType
        property scaffold_remote : String?
        property agents_mode : AgentsMode
        property minimal_config : Bool

        def initialize(
          @path : String = ".",
          @force : Bool = false,
          @clean : Bool = false,
          @skip_agents_md : Bool = false,
          @skip_sample_content : Bool = false,
          @skip_taxonomies : Bool = false,
          @multilingual_languages : Array(String) = [] of String,
          @scaffold : ScaffoldType = ScaffoldType::Simple,
          @scaffold_remote : String? = nil,
          @agents_mode : AgentsMode = AgentsMode::Remote,
          @minimal_config : Bool = false,
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
