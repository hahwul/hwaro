require "../../models/config"
require "../../utils/logger"

module Hwaro
  module Content
    module Seo
      class Llms
        def self.generate(config : Models::Config, output_dir : String, verbose : Bool = false)
          return unless config.llms.enabled

          content = config.llms.instructions
          # Add a newline at the end if not present and content is not empty
          content += "\n" if !content.empty? && !content.ends_with?("\n")

          filename = config.llms.filename
          file_path = File.join(output_dir, filename)
          File.write(file_path, content)
          Logger.action :create, file_path if verbose
          Logger.info "  Generated #{filename}"
        end
      end
    end
  end
end
