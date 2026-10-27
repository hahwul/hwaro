# WebP encoder in pure Crystal — no libwebp, nothing to link.
#
# stb_image_write (the rest of the image pipeline) cannot write WebP, and
# hwaro ships no external codec, so the encoder lives here:
#
#   quality 1-99  lossy VP8 key frame (RFC 6386); an alpha channel goes into
#                 an ALPH chunk, losslessly (VP8X + ALPH + VP8)
#   quality 100   lossless VP8L
#
# Every predictor, transform and context rule in the VP8 part mirrors the
# libwebp / RFC 6386 decoder bit for bit: intra prediction reads the
# reconstructed neighbours, so any drift would compound across the frame.
# The encoder side (mode decision, quantizer bias, filter strength) follows
# libwebp's defaults closely enough that `quality` means roughly the same
# thing as `cwebp -q`.
#
# Deliberately not done (each costs size, never correctness): segmentation,
# trellis quantization, multiple token partitions, VP8L predictor /
# cross-colour / palette transforms and colour cache.

require "./webp_encoder/tables"
require "./webp_encoder/vp8"
require "./webp_encoder/vp8l"

module Hwaro
  module Content
    module Processors
      module WebpEncoder
        extend self

        # Largest width/height a WebP canvas can carry (14-bit fields).
        MAX_DIMENSION = 16383

        # A complete `.webp` file for `pixels`: `width`×`height` samples of
        # `channels` interleaved bytes (1 gray, 2 gray+alpha, 3 RGB, 4 RGBA).
        # nil when the size is outside WebP's range or the frame cannot be
        # coded (a partition overflowing its 19-bit size field).
        def encode(pixels : Bytes, width : Int32, height : Int32, channels : Int32, quality : Int32) : Bytes?
          return unless width.in?(1..MAX_DIMENSION) && height.in?(1..MAX_DIMENSION) && channels.in?(1..4)
          return unless pixels.size >= width.to_i64 * height * channels
          quality = quality.clamp(1, 100)
          alpha = alpha_plane(pixels, width, height, channels)

          if quality == 100
            return riff({"VP8L", Lossless.encode(argb(pixels, width, height, channels), width, height, !alpha.nil?)})
          end

          return unless frame = VP8.new(pixels, width, height, channels, quality).encode
          return riff({"VP8 ", frame}) unless alpha

          vp8x = Bytes.new(10)
          vp8x[0] = 0x10_u8 # alpha flag
          put_le24(vp8x, 4, width - 1)
          put_le24(vp8x, 7, height - 1)
          riff({"VP8X", vp8x}, {"ALPH", Lossless.encode_alpha(alpha, width, height)}, {"VP8 ", frame})
        end

        # The alpha samples, or nil when the image has none or every one is
        # opaque (the simple, alpha-less file is smaller and equivalent).
        private def alpha_plane(pixels : Bytes, width : Int32, height : Int32, channels : Int32) : Bytes?
          return unless channels == 2 || channels == 4
          count = width * height
          alpha = Bytes.new(count) { |i| pixels[i * channels + channels - 1] }
          alpha.any? { |a| a != 255 } ? alpha : nil
        end

        # Pixels as VP8L ARGB words.
        private def argb(pixels : Bytes, width : Int32, height : Int32, channels : Int32) : Slice(UInt32)
          Slice(UInt32).new(width * height) do |i|
            p = i * channels
            r, g, b = channels >= 3 ? {pixels[p], pixels[p + 1], pixels[p + 2]} : {pixels[p], pixels[p], pixels[p]}
            a = channels == 2 || channels == 4 ? pixels[p + channels - 1] : 255_u8
            a.to_u32 << 24 | r.to_u32 << 16 | g.to_u32 << 8 | b.to_u32
          end
        end

        # RIFF container: each chunk is FourCC + LE32 size + payload, padded
        # to an even length.
        private def riff(*chunks : {String, Bytes}) : Bytes
          body = chunks.sum { |(_, data)| 8 + data.size + (data.size & 1) }
          io = IO::Memory.new(12 + body)
          io << "RIFF"
          io.write_bytes((4 + body).to_u32, IO::ByteFormat::LittleEndian)
          io << "WEBP"
          chunks.each do |(tag, data)|
            io << tag
            io.write_bytes(data.size.to_u32, IO::ByteFormat::LittleEndian)
            io.write(data)
            io.write_byte(0_u8) if data.size.odd?
          end
          io.to_slice
        end

        private def put_le24(buf : Bytes, at : Int32, value : Int32) : Nil
          buf[at] = (value & 0xFF).to_u8
          buf[at + 1] = ((value >> 8) & 0xFF).to_u8
          buf[at + 2] = ((value >> 16) & 0xFF).to_u8
        end
      end
    end
  end
end
