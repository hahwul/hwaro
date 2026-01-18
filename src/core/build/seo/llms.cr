require "../../../schemas/config"
require "../../../utils/logger"

module Hwaro
  module Core
    module Build
      module Seo
        class Llms
          def self.generate(config : Schemas::Config, output_dir : String)
            return unless config.seo.llms.enabled

            content = config.seo.llms.instructions
            # Add a newline at the end if not present and content is not empty
            content += "\n" if !content.empty? && !content.ends_with?("\n")

            filename = config.seo.llms.filename
            file_path = File.join(output_dir, filename)
            File.write(file_path, content)
            Logger.action :create, file_path
            Logger.info "  Generated #{filename}"
          end
        end
      end
    end
  end
end
