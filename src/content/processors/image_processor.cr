# Image processor for Hwaro
#
# Resizes images using stb libraries (statically linked, zero runtime dependencies):
# - stb_image.h        (decode JPG/PNG/BMP/GIF/TGA/PSD/HDR/PIC)
# - stb_image_write.h  (encode JPG/PNG/BMP)
# - stb_image_resize2.h (high-quality resize)
#
# Only JPG/PNG/BMP are supported for output because stb_image_write
# can only encode those formats. GIF/TGA/PSD/HDR can be decoded but
# not written back, so they are excluded from IMAGE_EXTENSIONS.
#
# Usage in templates:
#   {{ resize_image(path="images/photo.jpg", width=800, height=600) }}
#
# Config (config.toml):
#   [image_processing]
#   enabled = true
#   widths = [320, 640, 1024, 1280]
#   quality = 85

require "../../ext/stb_bindings"
require "../../models/config"

module Hwaro
  module Content
    module Processors
      module ImageProcessor
        extend self

        # Only formats that stb can both read AND write back correctly.
        IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp"}

        # Maximum pixel count to prevent excessive memory allocation (64 megapixels)
        MAX_PIXELS = 64_000_000_i64

        # Check if a file is a resizable image based on extension
        def image?(path : String) : Bool
          ext = File.extname(path).downcase
          IMAGE_EXTENSIONS.includes?(ext)
        end

        # Generate a resized filename: photo.jpg -> photo_800w.jpg
        def resized_filename(original : String, width : Int32) : String
          ext = File.extname(original)
          base = File.basename(original, ext)
          dir = File.dirname(original)
          name = "#{base}_#{width}w#{ext}"
          dir == "." ? name : File.join(dir, name)
        end

        # Resize a single image to the given width, preserving aspect ratio.
        # Returns the output path on success, nil on failure.
        def resize(source : String, dest : String, width : Int32, height : Int32 = 0, quality : Int32 = 85) : String?
          return nil unless File.exists?(source)

          # Clamp quality to valid range for stb_image_write (1-100)
          quality = quality.clamp(1, 100)

          # Load source image
          src_w = uninitialized LibC::Int
          src_h = uninitialized LibC::Int
          channels = uninitialized LibC::Int
          pixels = LibStb.stbi_load(source, pointerof(src_w), pointerof(src_h), pointerof(channels), 0)

          if pixels.null?
            reason = String.new(LibStb.stbi_failure_reason)
            Logger.debug "Image load failed '#{source}': #{reason}"
            return nil
          end

          begin
            # Guard against degenerate images (0 or negative dimensions)
            if src_w <= 0 || src_h <= 0 || channels <= 0
              Logger.debug "Image has invalid dimensions '#{source}': #{src_w}x#{src_h}x#{channels}"
              return nil
            end

            # Calculate output dimensions (preserve aspect ratio)
            out_w, out_h = calculate_dimensions(src_w.to_i32, src_h.to_i32, width, height)
            if out_w <= 0 || out_h <= 0
              Logger.debug "Calculated invalid output dimensions for '#{source}': #{out_w}x#{out_h}"
              return nil
            end

            # Skip resize if output would be larger than source
            if out_w >= src_w && out_h >= src_h
              FileUtils.mkdir_p(File.dirname(dest))
              FileUtils.cp(source, dest)
              return dest
            end

            # Guard against excessive memory allocation (use Int64 to avoid overflow)
            buf_size = out_w.to_i64 * out_h.to_i64 * channels.to_i64
            if buf_size > MAX_PIXELS * 4 # 4 channels max
              Logger.debug "Output image too large '#{source}': #{out_w}x#{out_h}x#{channels} = #{buf_size} bytes"
              return nil
            end

            # Allocate output buffer with LibC.malloc for deterministic C interop
            out_pixels = LibC.malloc(buf_size).as(UInt8*)
            if out_pixels.null?
              Logger.debug "Failed to allocate #{buf_size} bytes for resize of '#{source}'"
              return nil
            end

            begin
              result = LibStb.stbir_resize_uint8_linear(
                pixels, src_w, src_h, 0,
                out_pixels, out_w, out_h, 0,
                channels
              )

              if result.null?
                Logger.debug "Resize failed for '#{source}'"
                return nil
              end

              # Write output
              FileUtils.mkdir_p(File.dirname(dest))
              ext = File.extname(dest).downcase
              ok = write_image(dest, ext, out_w, out_h, channels.to_i32, out_pixels, quality)
              unless ok
                Logger.debug "Failed to write resized image '#{dest}'"
              end
              ok ? dest : nil
            ensure
              LibC.free(out_pixels.as(Void*))
            end
          ensure
            LibStb.stbi_image_free(pixels.as(Void*))
          end
        end

        # Process all images for configured widths.
        # Returns array of {original_url, width, resized_url} tuples.
        def process_configured_widths(
          source_path : String,
          output_base : String,
          url_prefix : String,
          widths : Array(Int32),
          quality : Int32 = 85,
        ) : Array({String, Int32, String})
          results = [] of {String, Int32, String}
          return results unless File.exists?(source_path)

          widths.each do |width|
            resized_name = resized_filename(File.basename(source_path), width)
            dest_path = File.join(output_base, resized_name)
            if resize(source_path, dest_path, width, 0, quality)
              resized_url = url_prefix.rstrip("/") + "/" + resized_name
              results << {source_path, width, resized_url}
            end
          end

          results
        end

        # Resize a single source image to multiple widths with one decode pass.
        # Returns a Hash mapping width => dest_path for successful resizes.
        def resize_multi_widths(
          source : String,
          dest_dir : String,
          widths : Array(Int32),
          quality : Int32 = 85,
        ) : Hash(Int32, String)
          result_map = {} of Int32 => String
          return result_map unless File.exists?(source)

          quality = quality.clamp(1, 100)

          # Single decode
          src_w = uninitialized LibC::Int
          src_h = uninitialized LibC::Int
          channels = uninitialized LibC::Int
          pixels = LibStb.stbi_load(source, pointerof(src_w), pointerof(src_h), pointerof(channels), 0)

          if pixels.null?
            # Note: stbi_failure_reason() is not thread-safe, so we skip it
            # in this method which may be called from concurrent fibers.
            Logger.debug "Image load failed '#{source}'"
            return result_map
          end

          begin
            return result_map if src_w <= 0 || src_h <= 0 || channels <= 0

            ext = File.extname(source).downcase
            basename = File.basename(source, File.extname(source))
            FileUtils.mkdir_p(dest_dir)

            widths.each do |width|
              out_w, out_h = calculate_dimensions(src_w.to_i32, src_h.to_i32, width, 0)
              next if out_w <= 0 || out_h <= 0

              dest = File.join(dest_dir, "#{basename}_#{width}w#{ext}")

              # Skip resize if output would be larger than source
              if out_w >= src_w && out_h >= src_h
                FileUtils.cp(source, dest)
                result_map[width] = dest
                next
              end

              buf_size = out_w.to_i64 * out_h.to_i64 * channels.to_i64
              next if buf_size > MAX_PIXELS * 4

              out_pixels = LibC.malloc(buf_size).as(UInt8*)
              next if out_pixels.null?

              begin
                resized = LibStb.stbir_resize_uint8_linear(
                  pixels, src_w, src_h, 0,
                  out_pixels, out_w, out_h, 0,
                  channels
                )
                next if resized.null?

                if write_image(dest, ext, out_w, out_h, channels.to_i32, out_pixels, quality)
                  result_map[width] = dest
                end
              ensure
                LibC.free(out_pixels.as(Void*))
              end
            end
          ensure
            LibStb.stbi_image_free(pixels.as(Void*))
          end

          result_map
        end

        # --- Private helpers ---

        # Calculate output dimensions preserving aspect ratio.
        # Returns {0, 0} for invalid inputs to signal caller to skip.
        private def calculate_dimensions(src_w : Int32, src_h : Int32, target_w : Int32, target_h : Int32) : {Int32, Int32}
          # Guard against zero source dimensions (prevents division by zero)
          return {0, 0} if src_w <= 0 || src_h <= 0

          if target_w > 0 && target_h > 0
            # Both specified: fit within the box
            scale_w = target_w.to_f / src_w
            scale_h = target_h.to_f / src_h
            scale = Math.min(scale_w, scale_h)
            {Math.max(1, (src_w * scale).round.to_i32), Math.max(1, (src_h * scale).round.to_i32)}
          elsif target_w > 0
            # Width only: scale proportionally
            scale = target_w.to_f / src_w
            {target_w, Math.max(1, (src_h * scale).round.to_i32)}
          elsif target_h > 0
            # Height only: scale proportionally
            scale = target_h.to_f / src_h
            {Math.max(1, (src_w * scale).round.to_i32), target_h}
          else
            {src_w, src_h}
          end
        end

        # Write image in the appropriate format based on extension
        private def write_image(path : String, ext : String, w : Int32, h : Int32, channels : Int32, data : UInt8*, quality : Int32) : Bool
          case ext
          when ".png"
            LibStb.stbi_write_png(path, w, h, channels, data.as(Void*), w * channels) != 0
          when ".jpg", ".jpeg"
            LibStb.stbi_write_jpg(path, w, h, channels, data.as(Void*), quality) != 0
          when ".bmp"
            LibStb.stbi_write_bmp(path, w, h, channels, data.as(Void*)) != 0
          else
            false
          end
        end
      end
    end
  end
end
