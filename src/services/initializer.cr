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
        run(options.path, options.force, options.skip_agents_md, options.skip_sample_content, options.skip_taxonomies)
      end

      def run(target_path : String, force : Bool = false, skip_agents_md : Bool = false, skip_sample_content : Bool = false, skip_taxonomies : Bool = false)
        unless Dir.exists?(target_path)
          Dir.mkdir_p(target_path)
        end

        unless force || Dir.empty?(target_path)
          Logger.error "Directory '#{target_path}' is not empty."
          Logger.error "Use --force to overwrite."
          exit(1)
        end

        Logger.info "Initializing new Hwaro project in #{target_path}..."

        create_directory(File.join(target_path, "content"))
        unless skip_sample_content
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

        create_directory(File.join(target_path, "static"))
        if skip_taxonomies
          create_file(File.join(target_path, "config.toml"), Defaults::ConfigSamples.config_without_taxonomies)
        else
          create_file(File.join(target_path, "config.toml"), Defaults::ConfigSamples.config)
        end

        unless skip_agents_md
          create_file(File.join(target_path, "AGENTS.md"), "")
        end

        Logger.success "Done! Run `hwaro build` to generate the site."
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
