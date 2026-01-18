require "../../../schemas/config"
require "../../../utils/logger"

module Hwaro
  module Core
    module Build
      module Seo
        class Robots
          def self.generate(config : Schemas::Config, output_dir : String)
            return unless config.robots.enabled

            content = String.build do |str|
              # Add rules
              config.robots.rules.each do |rule|
                str << "User-agent: #{rule.user_agent}\n"

                rule.allow.each do |path|
                  str << "Allow: #{path}\n"
                end

                rule.disallow.each do |path|
                  str << "Disallow: #{path}\n"
                end

                str << "\n"
              end

              # Default rule if no rules provided
              if config.robots.rules.empty?
                str << "User-agent: *\n"
                str << "Allow: /\n"
                str << "\n"
              end

              # Add Sitemap directive if sitemap is enabled and base_url is set
              if config.sitemap.enabled && !config.base_url.empty?
                base_url = config.base_url.rstrip('/')
                sitemap_filename = config.sitemap.filename
                # Ensure filename doesn't start with / if base_url doesn't end with /
                # But we stripped / from base_url, so we need / separator unless filename has it (which it shouldn't typically)
                # Usually sitemap is at root.
                sitemap_url = "#{base_url}/#{sitemap_filename}"
                str << "Sitemap: #{sitemap_url}\n"
              end
            end

            filename = config.robots.filename
            file_path = File.join(output_dir, filename)
            File.write(file_path, content)
            Logger.action :create, file_path
            Logger.info "  Generated robots.txt"
          end
        end
      end
    end
  end
end
