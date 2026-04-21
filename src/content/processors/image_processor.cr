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

require "base64"
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
          return unless File.exists?(source)

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
            return
          end

          begin
            # Guard against degenerate images (0 or negative dimensions)
            if src_w <= 0 || src_h <= 0 || channels <= 0
              Logger.debug "Image has invalid dimensions '#{source}': #{src_w}x#{src_h}x#{channels}"
              return
            end

            # Calculate output dimensions (preserve aspect ratio)
            out_w, out_h = calculate_dimensions(src_w.to_i32, src_h.to_i32, width, height)
            if out_w <= 0 || out_h <= 0
              Logger.debug "Calculated invalid output dimensions for '#{source}': #{out_w}x#{out_h}"
              return
            end

            # Skip resize if output would be larger than source
            if out_w >= src_w && out_h >= src_h
              FileUtils.mkdir_p(File.dirname(dest))
              FileUtils.cp(source, dest)
              return dest
            end

            # Guard against excessive memory allocation
            # Check pixel count before multiplying by channels to prevent Int64 overflow
            pixel_count = out_w.to_i64 * out_h.to_i64
            if pixel_count > MAX_PIXELS
              Logger.debug "Output image too large '#{source}': #{out_w}x#{out_h} = #{pixel_count} pixels"
              return
            end
            buf_size = pixel_count * channels.to_i64

            # Allocate output buffer with LibC.malloc for deterministic C interop
            out_pixels = LibC.malloc(buf_size).as(UInt8*)
            if out_pixels.null?
              Logger.debug "Failed to allocate #{buf_size} bytes for resize of '#{source}'"
              return
            end

            begin
              result = LibStb.stbir_resize_uint8_linear(
                pixels, src_w, src_h, 0,
                out_pixels, out_w, out_h, 0,
                channels
              )

              if result.null?
                Logger.debug "Resize failed for '#{source}'"
                return
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
              LibC.free(out_pixels.as(Void*)) unless out_pixels.null?
            end
          ensure
            LibStb.stbi_image_free(pixels.as(Void*)) unless pixels.null?
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
          result_map, _, _ = resize_and_lqip(source, dest_dir, widths, quality, 0, 20)
          result_map
        end

        # Generate a low-quality image placeholder as a base64 data URI.
        # Operates on already-decoded pixel data (avoids a second stbi_load).
        def generate_lqip(pixels : UInt8*, src_w : Int32, src_h : Int32, channels : Int32,
                          lqip_width : Int32 = 32, quality : Int32 = 20) : String?
          result = generate_lqip_with_color(pixels, src_w, src_h, channels, lqip_width, quality)
          result.try(&.[0])
        end

        # Generate LQIP data URI and dominant color from the thumbnail in one pass.
        # Returns {data_uri, dominant_color_hex} or nil on failure.
        def generate_lqip_with_color(pixels : UInt8*, src_w : Int32, src_h : Int32, channels : Int32,
                                     lqip_width : Int32 = 32, quality : Int32 = 20) : {String, String}?
          return if lqip_width <= 0
          return if src_w <= 0 || src_h <= 0 || channels <= 0

          # Don't upscale — cap thumbnail width to source width
          effective_width = Math.min(lqip_width, src_w)
          out_w, out_h = calculate_dimensions(src_w, src_h, effective_width, 0)
          return if out_w <= 0 || out_h <= 0

          pixel_count = out_w.to_i64 * out_h.to_i64
          return if pixel_count > MAX_PIXELS
          buf_size = pixel_count * channels.to_i64

          thumb_pixels = LibC.malloc(buf_size).as(UInt8*)
          return if thumb_pixels.null?

          begin
            resized = LibStb.stbir_resize_uint8_linear(
              pixels, src_w, src_h, 0,
              thumb_pixels, out_w, out_h, 0,
              channels
            )
            return if resized.null?

            # Compute dominant color from the tiny thumbnail (cheap)
            dom_color = dominant_color(thumb_pixels, out_w, out_h, channels)

            jpg_buf = Pointer(UInt8).null
            jpg_len = 0_i32
            ok = LibStb.hwaro_write_jpg_to_mem(
              thumb_pixels, out_w, out_h, channels,
              quality, pointerof(jpg_buf), pointerof(jpg_len)
            )
            return if ok == 0 || jpg_buf.null? || jpg_len <= 0

            begin
              bytes = Bytes.new(jpg_buf, jpg_len)
              b64 = Base64.strict_encode(bytes)
              {"data:image/jpeg;base64,#{b64}", dom_color}
            ensure
              LibC.free(jpg_buf.as(Void*))
            end
          ensure
            LibC.free(thumb_pixels.as(Void*))
          end
        end

        # Compute dominant color as a hex string (e.g., "#a3b2c1").
        # Channels: 1=gray, 2=gray+alpha, 3=RGB, 4=RGBA
        def dominant_color(pixels : UInt8*, w : Int32, h : Int32, channels : Int32) : String
          return "#000000" if w <= 0 || h <= 0 || channels <= 0

          total = w.to_i64 * h.to_i64
          return "#000000" if total == 0

          sum_r = 0_i64
          sum_g = 0_i64
          sum_b = 0_i64

          is_rgb = channels >= 3 # 3=RGB, 4=RGBA

          total.times do |i|
            offset = i * channels
            sum_r += pixels[offset]
            if is_rgb
              sum_g += pixels[offset + 1]
              sum_b += pixels[offset + 2]
            end
          end

          r = (sum_r // total).clamp(0, 255)
          g = is_rgb ? (sum_g // total).clamp(0, 255) : r
          b = is_rgb ? (sum_b // total).clamp(0, 255) : r

          "#%02x%02x%02x" % {r, g, b}
        end

        # Combined resize + LQIP in a single decode pass.
        # Returns {width_map, lqip_data_uri_or_nil, dominant_color_hex}
        def resize_and_lqip(
          source : String,
          dest_dir : String,
          widths : Array(Int32),
          quality : Int32 = 85,
          lqip_width : Int32 = 32,
          lqip_quality : Int32 = 20,
        ) : {Hash(Int32, String), String?, String}
          result_map = {} of Int32 => String
          lqip_uri = nil
          dom_color = "#000000"

          return {result_map, lqip_uri, dom_color} unless File.exists?(source)
          quality = quality.clamp(1, 100)

          src_w = uninitialized LibC::Int
          src_h = uninitialized LibC::Int
          channels = uninitialized LibC::Int
          pixels = LibStb.stbi_load(source, pointerof(src_w), pointerof(src_h), pointerof(channels), 0)

          if pixels.null?
            Logger.debug "Image load failed '#{source}'"
            return {result_map, lqip_uri, dom_color}
          end

          # Declare outside begin so ensure always has a valid pointer to free
          smallest_pixels : UInt8* = Pointer(UInt8).null
          smallest_w = 0_i32
          smallest_h = 0_i32

          begin
            return {result_map, lqip_uri, dom_color} if src_w <= 0 || src_h <= 0 || channels <= 0

            ext = File.extname(source).downcase
            basename = File.basename(source, File.extname(source))
            FileUtils.mkdir_p(dest_dir)

            # Resize variants (sorted ascending so smallest is processed first)
            sorted_widths = widths.sort
            sorted_widths.each do |width|
              out_w, out_h = calculate_dimensions(src_w.to_i32, src_h.to_i32, width, 0)
              next if out_w <= 0 || out_h <= 0

              dest = File.join(dest_dir, "#{basename}_#{width}w#{ext}")

              if out_w >= src_w && out_h >= src_h
                FileUtils.cp(source, dest)
                result_map[width] = dest
                next
              end

              pixel_count = out_w.to_i64 * out_h.to_i64
              next if pixel_count > MAX_PIXELS
              buf_size = pixel_count * channels.to_i64

              out_pixels = LibC.malloc(buf_size).as(UInt8*)
              next if out_pixels.null?

              begin
                resized = LibStb.stbir_resize_uint8_linear(
                  pixels, src_w, src_h, 0,
                  out_pixels, out_w, out_h, 0,
                  channels
                )
                unless resized.null?
                  if write_image(dest, ext, out_w, out_h, channels.to_i32, out_pixels, quality)
                    result_map[width] = dest
                  end

                  # Keep the smallest variant alive as LQIP source
                  if lqip_width > 0 && smallest_pixels.null?
                    smallest_pixels = out_pixels
                    smallest_w = out_w
                    smallest_h = out_h
                    out_pixels = Pointer(UInt8).null
                  end
                end
              ensure
                LibC.free(out_pixels.as(Void*)) unless out_pixels.null?
              end
            end

            # LQIP generation — use smallest resize variant as source when available
            # (e.g. 320px → 32px is ~155× cheaper than 4000px → 32px)
            if lqip_width > 0
              lqip_src = smallest_pixels.null? ? pixels : smallest_pixels
              lqip_src_w = smallest_pixels.null? ? src_w.to_i32 : smallest_w
              lqip_src_h = smallest_pixels.null? ? src_h.to_i32 : smallest_h

              lqip_result = generate_lqip_with_color(lqip_src, lqip_src_w, lqip_src_h, channels.to_i32, lqip_width, lqip_quality)
              if lqip_result
                lqip_uri = lqip_result[0]
                dom_color = lqip_result[1]
              end
            end
          ensure
            LibC.free(smallest_pixels.as(Void*)) unless smallest_pixels.null?
            LibStb.stbi_image_free(pixels.as(Void*)) unless pixels.null?
          end

          {result_map, lqip_uri, dom_color}
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
