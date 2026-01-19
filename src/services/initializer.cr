# Initializer module for creating new Hwaro projects
#
# Creates the initial project structure with sample content,
# templates, and configuration.

require "../config/options/init_options"
require "../utils/logger"
require "../services/defaults/content"
require "../services/defaults/templates"
require "../services/defaults/config"

module Hwaro
  module Services
    class Initializer
      def run(options : Config::Options::InitOptions)
        run(
          options.path,
          options.force,
          options.skip_agents_md,
          options.skip_sample_content,
          options.skip_taxonomies,
          options.multilingual_languages
        )
      end

      def run(
        target_path : String,
        force : Bool = false,
        skip_agents_md : Bool = false,
        skip_sample_content : Bool = false,
        skip_taxonomies : Bool = false,
        multilingual_languages : Array(String) = [] of String
      )
        unless Dir.exists?(target_path)
          Dir.mkdir_p(target_path)
        end

        unless force || Dir.empty?(target_path)
          Logger.error "Directory '#{target_path}' is not empty."
          Logger.error "Use --force to overwrite."
          exit(1)
        end

        Logger.info "Initializing new Hwaro project in #{target_path}..."

        is_multilingual = multilingual_languages.size > 1

        # Create content structure
        create_directory(File.join(target_path, "content"))

        unless skip_sample_content
          if is_multilingual
            create_multilingual_content(target_path, multilingual_languages, skip_taxonomies)
          else
            create_single_language_content(target_path, skip_taxonomies)
          end
        end

        # Create templates
        create_templates(target_path, skip_taxonomies)

        # Create static directory
        create_directory(File.join(target_path, "static"))

        # Create config.toml
        config_content = if is_multilingual
                           Defaults::ConfigSamples.config_multilingual(multilingual_languages, skip_taxonomies)
                         elsif skip_taxonomies
                           Defaults::ConfigSamples.config_without_taxonomies
                         else
                           Defaults::ConfigSamples.config
                         end
        create_file(File.join(target_path, "config.toml"), config_content)

        # Create AGENTS.md unless skipped
        unless skip_agents_md
          create_file(File.join(target_path, "AGENTS.md"), "")
        end

        Logger.success "Done! Run `hwaro build` to generate the site."
      end

      private def create_single_language_content(target_path : String, skip_taxonomies : Bool)
        if skip_taxonomies
          create_file(File.join(target_path, "content", "index.md"), Defaults::ContentSamples.index_content_simple)
          create_file(File.join(target_path, "content", "about.md"), Defaults::ContentSamples.about_content_simple)
        else
          create_file(File.join(target_path, "content", "index.md"), Defaults::ContentSamples.index_content)
          create_file(File.join(target_path, "content", "about.md"), Defaults::ContentSamples.about_content)

          create_directory(File.join(target_path, "content", "blog"))
          create_file(File.join(target_path, "content", "blog", "_index.md"), Defaults::ContentSamples.blog_index_content)
          create_file(File.join(target_path, "content", "blog", "hello-world.md"), Defaults::ContentSamples.blog_post_content)
        end
      end

      private def create_multilingual_content(target_path : String, languages : Array(String), skip_taxonomies : Bool)
        default_lang = languages.first
        content_dir = File.join(target_path, "content")

        languages.each_with_index do |lang, index|
          is_default = index == 0

          if is_default
            # Default language content goes directly as filename.md
            create_file(
              File.join(content_dir, "index.md"),
              Defaults::ContentSamples.index_content_multilingual(lang, true, skip_taxonomies)
            )
            create_file(
              File.join(content_dir, "about.md"),
              Defaults::ContentSamples.about_content_multilingual(lang, skip_taxonomies)
            )

            unless skip_taxonomies
              create_directory(File.join(content_dir, "blog"))
              create_file(
                File.join(content_dir, "blog", "_index.md"),
                Defaults::ContentSamples.blog_index_content_multilingual(lang)
              )
              create_file(
                File.join(content_dir, "blog", "hello-world.md"),
                Defaults::ContentSamples.blog_post_content_multilingual(lang, skip_taxonomies)
              )
            end
          else
            # Non-default languages go as filename.lang.md in same directory
            create_file(
              File.join(content_dir, "index.#{lang}.md"),
              Defaults::ContentSamples.index_content_multilingual(lang, false, skip_taxonomies)
            )
            create_file(
              File.join(content_dir, "about.#{lang}.md"),
              Defaults::ContentSamples.about_content_multilingual(lang, skip_taxonomies)
            )

            unless skip_taxonomies
              create_file(
                File.join(content_dir, "blog", "_index.#{lang}.md"),
                Defaults::ContentSamples.blog_index_content_multilingual(lang)
              )
              create_file(
                File.join(content_dir, "blog", "hello-world.#{lang}.md"),
                Defaults::ContentSamples.blog_post_content_multilingual(lang, skip_taxonomies)
              )
            end
          end
        end
      end

      private def create_templates(target_path : String, skip_taxonomies : Bool)
        create_directory(File.join(target_path, "templates"))
        create_file(File.join(target_path, "templates", "header.ecr"), Defaults::TemplateSamples.header)
        create_file(File.join(target_path, "templates", "footer.ecr"), Defaults::TemplateSamples.footer)
        create_file(File.join(target_path, "templates", "page.ecr"), Defaults::TemplateSamples.page)
        create_file(File.join(target_path, "templates", "section.ecr"), Defaults::TemplateSamples.section)

        unless skip_taxonomies
          create_file(File.join(target_path, "templates", "taxonomy.ecr"), Defaults::TemplateSamples.taxonomy)
          create_file(File.join(target_path, "templates", "taxonomy_term.ecr"), Defaults::TemplateSamples.taxonomy_term)
        end

        create_file(File.join(target_path, "templates", "404.ecr"), Defaults::TemplateSamples.not_found)

        create_directory(File.join(target_path, "templates", "shortcodes"))
        create_file(File.join(target_path, "templates", "shortcodes", "alert.ecr"), Defaults::TemplateSamples.alert)
      end

      private def create_directory(path : String)
        unless Dir.exists?(path)
          Dir.mkdir_p(path)
          Logger.action :create, path
        else
          Logger.action :exist, path, :blue
        end
      end

      private def create_file(path : String, content : String)
        unless File.exists?(path)
          File.write(path, content)
          Logger.action :create, path
        else
          Logger.action :exist, path, :blue
        end
      end
    end
  end
end
