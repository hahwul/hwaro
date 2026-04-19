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

        # Class-level map: original_url => { "lqip" => data_uri, "dominant_color" => hex }
        @@lqip_map = {} of String => Hash(String, String)
        @@lqip_map_mutex = Mutex.new

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

        def self.lqip_map : Hash(String, Hash(String, String))
          @@lqip_map_mutex.synchronize { @@lqip_map.dup }
        end

        def self.set_lqip_map(map : Hash(String, Hash(String, String)))
          @@lqip_map_mutex.synchronize { @@lqip_map = map }
        end

        def self.find_lqip(url : String) : Hash(String, String)?
          @@lqip_map_mutex.synchronize { @@lqip_map[url]?.try(&.dup) }
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
          if ctx.options.skip_image_processing
            Logger.debug "  Skipping image processing (--skip-image-processing)"
            return
          end
          return unless config.image_processing.enabled
          return if config.image_processing.widths.empty?

          widths = config.image_processing.widths
          quality = config.image_processing.quality
          lqip_enabled = config.image_processing.lqip_enabled
          lqip_width = lqip_enabled ? config.image_processing.lqip_width : 0
          lqip_quality = config.image_processing.lqip_quality
          output_dir = ctx.output_dir
          resolved_output = File.expand_path(output_dir)

          # Phase 1: Collect all image jobs (fast, single-threaded)
          jobs = [] of ImageJob
          seen = Set(String).new
          collect_page_asset_jobs(ctx, output_dir, resolved_output, jobs, seen)
          collect_content_file_jobs(config, output_dir, resolved_output, jobs, seen) if config.content_files.enabled?
          collect_static_jobs(output_dir, resolved_output, jobs, seen)

          return if jobs.empty?

          # Phase 2: Split jobs into "already fresh" (reuse from previous
          # rebuild's maps) and "needs work". Snapshot previous maps first
          # so watch-triggered rebuilds don't re-decode unchanged images.
          # Without this, adding one image to a serve session re-processes
          # every image in the project (see issue #389).
          previous_resize_map = @@resize_map_mutex.synchronize { @@resize_map.dup }
          previous_lqip_map = @@lqip_map_mutex.synchronize { @@lqip_map.dup }

          new_map = {} of String => Hash(Int32, String)
          new_lqip_map = {} of String => Hash(String, String)
          jobs_to_process = [] of ImageJob
          reused_count = 0

          jobs.each do |job|
            reused_widths = self.class.reusable_widths(job.source_path, job.dest_dir, widths)
            if reused_widths && (!lqip_enabled || previous_lqip_map.has_key?(job.original_url))
              width_urls = {} of Int32 => String
              reused_widths.each do |width, filename|
                width_urls[width] = job.url_prefix + filename
              end
              new_map[job.original_url] = width_urls
              if lqip_enabled && (lqip = previous_lqip_map[job.original_url]?)
                new_lqip_map[job.original_url] = lqip
              end
              reused_count += 1
            else
              jobs_to_process << job
            end
          end

          if jobs_to_process.empty?
            @@resize_map_mutex.synchronize { @@resize_map = new_map }
            @@lqip_map_mutex.synchronize { @@lqip_map = new_lqip_map }
            Logger.debug "  Image processing: reused #{reused_count} cached result(s); no decode needed."
            return
          end

          # Phase 3: Process the work set in parallel with bounded concurrency
          map_mutex = Mutex.new
          work_channel = Channel(ImageJob?).new(CONCURRENCY)
          done_channel = Channel(Nil).new

          # Spawn worker fibers
          CONCURRENCY.times do
            spawn do
              while job = work_channel.receive?
                width_map, lqip_data = resize_one(job, widths, quality, lqip_width, lqip_quality)
                map_mutex.synchronize do
                  new_map[job.original_url] = width_map unless width_map.empty?
                  new_lqip_map[job.original_url] = lqip_data if lqip_data
                end
              end
              done_channel.send(nil)
            end
          end

          # Feed jobs
          jobs_to_process.each { |job| work_channel.send(job) }
          CONCURRENCY.times { work_channel.send(nil) } # sentinel to stop workers

          # Wait for all workers
          CONCURRENCY.times { done_channel.receive }

          @@resize_map_mutex.synchronize { @@resize_map = new_map }
          @@lqip_map_mutex.synchronize { @@lqip_map = new_lqip_map }
          resized_count = jobs_to_process.size
          Logger.success "  Generated #{resized_count} resized image(s)." if resized_count > 0
          Logger.debug "  Image processing: reused #{reused_count} cached result(s)." if reused_count > 0
          Logger.success "  Generated #{new_lqip_map.size} LQIP placeholder(s)." if new_lqip_map.size > 0
        end

        # Returns a `width => filename` map when every expected destination
        # file already exists on disk with an mtime at least as new as the
        # source (i.e. decoding/resizing would produce bit-identical output).
        # Returns nil when any destination is missing or stale — caller then
        # processes the image normally. Caller must also verify LQIP cache
        # separately; LQIP can't be reconstructed from disk bytes.
        def self.reusable_widths(
          source_path : String,
          dest_dir : String,
          widths : Array(Int32),
        ) : Hash(Int32, String)?
          return nil unless File.exists?(source_path)
          source_mtime = File.info(source_path).modification_time

          ext = File.extname(source_path)
          basename = File.basename(source_path, ext)
          result = {} of Int32 => String
          widths.each do |width|
            filename = "#{basename}_#{width}w#{ext}"
            dest = File.join(dest_dir, filename)
            return nil unless File.exists?(dest)
            return nil if File.info(dest).modification_time < source_mtime
            result[width] = filename
          end
          result
        end

        # Resize a single image to all widths + generate LQIP (one decode pass)
        private def resize_one(job : ImageJob, widths : Array(Int32), quality : Int32,
                               lqip_width : Int32, lqip_quality : Int32) : {Hash(Int32, String), Hash(String, String)?}
          path_map, lqip_uri, dom_color = Processors::ImageProcessor.resize_and_lqip(
            job.source_path, job.dest_dir, widths, quality, lqip_width, lqip_quality
          )

          width_url_map = {} of Int32 => String
          path_map.each do |width, dest_path|
            resized_name = File.basename(dest_path)
            width_url_map[width] = job.url_prefix + resized_name
          end

          lqip_data = if lqip_uri
                        {"lqip" => lqip_uri, "dominant_color" => dom_color}
                      else
                        nil
                      end

          {width_url_map, lqip_data}
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
