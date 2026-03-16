# Image processing hooks for build lifecycle
#
# Processes images during the Write phase, generating resized variants
# for configured widths. The resized image map is exposed to the
# `resize_image()` template function.
#
# Performance:
# - Each source image is decoded only once (resize_multi_widths)
# - Images are processed in parallel using fibers

require "../../core/lifecycle"
require "../processors/image_processor"

module Hwaro
  module Content
    module Hooks
      class ImageHooks
        include Core::Lifecycle::Hookable

        # Class-level map: original_url => { width => resized_url }
        @@resize_map = {} of String => Hash(Int32, String)
        @@resize_map_mutex = Mutex.new

        # Max number of concurrent image processing fibers
        CONCURRENCY = 8

        def register_hooks(manager : Core::Lifecycle::Manager)
          # Run before Render so the resize map is populated when templates
          # call resize_image(). Source images live in content/ and static/
          # which are available at this point.
          manager.on(Core::Lifecycle::HookPoint::BeforeRender, priority: 20, name: "image:resize") do |ctx|
            process_images(ctx)
            Core::Lifecycle::HookResult::Continue
          end
        end

        # Returns a snapshot copy of the resize map (safe to use outside mutex)
        def self.resize_map : Hash(String, Hash(Int32, String))
          @@resize_map_mutex.synchronize { @@resize_map.dup }
        end

        # Replace the resize map (used by tests)
        def self.set_resize_map(map : Hash(String, Hash(Int32, String)))
          @@resize_map_mutex.synchronize { @@resize_map = map }
        end

        def self.find_resized(url : String, width : Int32) : String?
          @@resize_map_mutex.synchronize do
            @@resize_map[url]?.try { |m| m[width]? }
          end
        end

        def self.find_closest(url : String, width : Int32) : String?
          @@resize_map_mutex.synchronize do
            widths_map = @@resize_map[url]?
            return nil unless widths_map
            return widths_map[width] if widths_map.has_key?(width)

            # Find the smallest width that is >= requested
            best_key = nil
            widths_map.each_key do |w|
              if w >= width
                if best_key.nil? || w < best_key
                  best_key = w
                end
              end
            end
            # If nothing bigger, pick the largest available
            best_key ||= widths_map.keys.max?
            best_key ? widths_map[best_key] : nil
          end
        end

        # Describes a single image to be resized
        private record ImageJob,
          source_path : String,
          dest_dir : String,
          original_url : String,
          url_prefix : String

        private def process_images(ctx : Core::Lifecycle::BuildContext)
          config = ctx.config
          return unless config
          return unless config.image_processing.enabled
          return if config.image_processing.widths.empty?

          widths = config.image_processing.widths
          quality = config.image_processing.quality
          output_dir = ctx.output_dir
          resolved_output = File.expand_path(output_dir)

          # Phase 1: Collect all image jobs (fast, single-threaded)
          jobs = [] of ImageJob
          seen = Set(String).new
          collect_page_asset_jobs(ctx, output_dir, resolved_output, jobs, seen)
          collect_content_file_jobs(config, output_dir, resolved_output, jobs, seen) if config.content_files.enabled?
          collect_static_jobs(output_dir, resolved_output, jobs, seen)

          return if jobs.empty?

          # Phase 2: Process in parallel with bounded concurrency
          new_map = {} of String => Hash(Int32, String)
          map_mutex = Mutex.new
          work_channel = Channel(ImageJob?).new(CONCURRENCY)
          done_channel = Channel(Nil).new

          # Spawn worker fibers
          CONCURRENCY.times do
            spawn do
              while job = work_channel.receive?
                width_map = resize_one(job, widths, quality)
                unless width_map.empty?
                  map_mutex.synchronize do
                    new_map[job.original_url] = width_map
                  end
                end
              end
              done_channel.send(nil)
            end
          end

          # Feed jobs
          jobs.each { |job| work_channel.send(job) }
          CONCURRENCY.times { work_channel.send(nil) } # sentinel to stop workers

          # Wait for all workers
          CONCURRENCY.times { done_channel.receive }

          @@resize_map_mutex.synchronize { @@resize_map = new_map }
          resized_count = new_map.values.sum(&.size)
          Logger.success "  Generated #{resized_count} resized image(s)." if resized_count > 0
        end

        # Resize a single image to all widths (one decode, N encodes)
        private def resize_one(job : ImageJob, widths : Array(Int32), quality : Int32) : Hash(Int32, String)
          path_map = Processors::ImageProcessor.resize_multi_widths(
            job.source_path, job.dest_dir, widths, quality
          )

          width_url_map = {} of Int32 => String
          path_map.each do |width, dest_path|
            resized_name = File.basename(dest_path)
            width_url_map[width] = job.url_prefix + resized_name
          end
          width_url_map
        end

        # --- Job collection helpers ---

        private def collect_page_asset_jobs(
          ctx : Core::Lifecycle::BuildContext,
          output_dir : String,
          resolved_output : String,
          jobs : Array(ImageJob),
          seen : Set(String),
        )
          ctx.all_pages.each do |page|
            next if page.assets.empty?

            page_bundle_dir = File.dirname(page.path)
            url_path = page.url.lchop("/")
            dest_dir = File.join(output_dir, url_path)

            page.assets.each do |asset_path|
              next unless Processors::ImageProcessor.image?(asset_path)

              source_path = File.join("content", asset_path)
              next unless File.exists?(source_path)
              next unless safe_path?(source_path, "content")

              relative_to_bundle = Path[asset_path].relative_to(page_bundle_dir)
              original_url = "/" + url_path + relative_to_bundle.to_s
              next if seen.includes?(original_url)
              asset_dest_dir = File.join(dest_dir, File.dirname(relative_to_bundle.to_s))
              next unless safe_path_dest?(asset_dest_dir, resolved_output)

              url_prefix = "/" + url_path + File.dirname(relative_to_bundle.to_s).rstrip(".") + "/"
              url_prefix = url_prefix.gsub("//", "/")

              seen.add(original_url)
              jobs << ImageJob.new(source_path, asset_dest_dir, original_url, url_prefix)
            end
          end
        end

        private def collect_content_file_jobs(
          config : Models::Config,
          output_dir : String,
          resolved_output : String,
          jobs : Array(ImageJob),
          seen : Set(String),
        )
          Dir.glob(File.join("content", "**", "*")).each do |file|
            next unless File.file?(file)
            next unless Processors::ImageProcessor.image?(file)
            next unless safe_path?(file, "content")
            relative = Path[file].relative_to("content").to_s
            next unless config.content_files.publish?(relative)

            original_url = "/" + relative
            next if seen.includes?(original_url)
            dest_dir = File.join(output_dir, File.dirname(relative))
            next unless safe_path_dest?(dest_dir, resolved_output)

            dir_part = File.dirname(relative)
            url_prefix = dir_part == "." ? "/" : "/#{dir_part}/"

            seen.add(original_url)
            jobs << ImageJob.new(file, dest_dir, original_url, url_prefix)
          end
        end

        private def collect_static_jobs(
          output_dir : String,
          resolved_output : String,
          jobs : Array(ImageJob),
          seen : Set(String),
        )
          return unless Dir.exists?("static")

          Dir.glob(File.join("static", "**", "*")).each do |file|
            next unless File.file?(file)
            next unless Processors::ImageProcessor.image?(file)
            next unless safe_path?(file, "static")

            relative = Path[file].relative_to("static").to_s
            original_url = "/" + relative
            next if seen.includes?(original_url)
            dest_dir = File.join(output_dir, File.dirname(relative))
            next unless safe_path_dest?(dest_dir, resolved_output)

            dir_part = File.dirname(relative)
            url_prefix = dir_part == "." ? "/" : "/#{dir_part}/"

            seen.add(original_url)
            jobs << ImageJob.new(file, dest_dir, original_url, url_prefix)
          end
        end

        # --- Security helpers ---

        # Verify that a source path resolves within the expected base directory.
        # Uses File.realpath to resolve symlinks before the boundary check.
        private def safe_path?(path : String, base : String) : Bool
          resolved = File.realpath(path) rescue return false
          resolved_base = File.realpath(base) rescue File.expand_path(base)
          resolved == resolved_base || resolved.starts_with?(resolved_base + "/")
        end

        # Verify destination directory is within output (dest may not exist yet)
        private def safe_path_dest?(path : String, resolved_output : String) : Bool
          resolved = File.expand_path(path)
          resolved == resolved_output || resolved.starts_with?(resolved_output + "/")
        end
      end
    end
  end
end
