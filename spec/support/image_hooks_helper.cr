# Test seams for ImageHooks' class-level maps, which a build fills only
# through the `image:resize` hook.
class Hwaro::Content::Hooks::ImageHooks
  def self.resize_map : Hash(String, Hash(Int32, String))
    @@resize_map_mutex.synchronize { @@resize_map.dup }
  end

  def self.set_resize_map(map : Hash(String, Hash(Int32, String)))
    @@resize_map_mutex.synchronize { @@resize_map = map }
  end

  def self.lqip_map : Hash(String, Hash(String, String))
    @@lqip_map_mutex.synchronize { @@lqip_map.dup }
  end

  def self.set_lqip_map(map : Hash(String, Hash(String, String)))
    @@lqip_map_mutex.synchronize { @@lqip_map = map }
  end

  # Forget the per-build intrinsic-size cache (keyed by project-relative
  # path, so specs in different temp projects would otherwise share it).
  def self.clear_intrinsic_sizes : Nil
    @@lookup_mutex.synchronize do
      @@intrinsic_sizes.clear
      @@render_image_sources.clear
    end
  end
end

# A real JPEG (`w`x`h`, horizontal gradient) with an Exif APP1 block carrying
# *orientation* inserted right after SOI, like a phone photo.
def write_exif_jpeg(path : String, w : Int32, h : Int32, orientation : Int32?, little : Bool = true) : Nil
  pixels = Bytes.new(w * h * 3) { |i| (((i // 3) % w) * 255 // w).to_u8 }
  LibStb.stbi_write_jpg(path, w, h, 3, pixels.to_unsafe.as(Void*), 90).should_not eq(0)
  return unless orientation

  fmt = little ? IO::ByteFormat::LittleEndian : IO::ByteFormat::BigEndian
  tiff = IO::Memory.new
  tiff.write(little ? "II".to_slice : "MM".to_slice)
  tiff.write_bytes(42_u16, fmt)
  tiff.write_bytes(8_u32, fmt)      # IFD0 offset
  tiff.write_bytes(1_u16, fmt)      # one entry
  tiff.write_bytes(0x0112_u16, fmt) # Orientation
  tiff.write_bytes(3_u16, fmt)      # SHORT
  tiff.write_bytes(1_u32, fmt)      # count
  tiff.write_bytes(orientation.to_u16, fmt)
  tiff.write_bytes(0_u16, fmt) # value padding
  tiff.write_bytes(0_u32, fmt) # next IFD
  segment = IO::Memory.new
  segment.write(Bytes[0xFF, 0xE1])
  segment.write_bytes((2 + 6 + tiff.size).to_u16, IO::ByteFormat::BigEndian)
  segment.write("Exif\0\0".to_slice)
  segment.write(tiff.to_slice)

  jpeg = File.open(path, "rb", &.getb_to_end)
  File.open(path, "wb") do |io|
    io.write(jpeg[0, 2])
    io.write(segment.to_slice)
    io.write(jpeg[2, jpeg.size - 2])
  end
end
