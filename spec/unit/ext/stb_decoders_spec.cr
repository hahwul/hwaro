require "../../spec_helper"

# stb_image picks a decoder by sniffing a file's content, not its extension.
# hwaro only needs JPEG/PNG/BMP (plus GIF for an OG logo), so the rest are
# compiled out of src/ext/stb_impl.c: a contributed `photo.png` that is really
# one of them must fail to decode and be skipped, not run through that decoder.
private def stb_decode(path : String) : {Bool, Int32, Int32}
  w = uninitialized LibC::Int
  h = uninitialized LibC::Int
  c = uninitialized LibC::Int
  pixels = LibStb.stbi_load(path, pointerof(w), pointerof(h), pointerof(c), 0)
  return {false, 0, 0} if pixels.null?
  LibStb.stbi_image_free(pixels.as(Void*))
  {true, w.to_i32, h.to_i32}
end

# Scribbles over the stack below the caller, so a decoder that reads an
# uninitialised local sees 0xAA instead of whatever zeros the spec runner left.
@[NoInline]
private def dirty_stack : Nil
  buf = StaticArray(UInt8, 16384).new(0xAA_u8)
  buf.to_unsafe.as(UInt8*).value = buf[100] # keep the writes alive
end

describe "stb_image decoders" do
  it "still decodes PNG, JPEG and BMP" do
    Dir.mktmpdir do |dir|
      rgb = Bytes.new(4 * 4 * 3) { |i| ((i * 7) & 0xFF).to_u8 }
      png = File.join(dir, "a.png")
      jpg = File.join(dir, "a.jpg")
      bmp = File.join(dir, "a.bmp")
      LibStb.stbi_write_png(png, 4, 4, 3, rgb.to_unsafe.as(Void*), 12).should_not eq 0
      LibStb.stbi_write_jpg(jpg, 4, 4, 3, rgb.to_unsafe.as(Void*), 90).should_not eq 0
      LibStb.stbi_write_bmp(bmp, 4, 4, 3, rgb.to_unsafe.as(Void*)).should_not eq 0
      [png, jpg, bmp].each { |path| stb_decode(path).should eq({true, 4, 4}) }
    end
  end

  it "does not decode a TGA, however it is named" do
    Dir.mktmpdir do |dir|
      # 2x2 uncompressed 24-bit TGA: no magic number, so stb tries it last.
      header = Bytes[0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 2, 0, 24, 0]
      path = File.join(dir, "photo.png")
      File.write(path, header + Bytes.new(12, 0x55_u8))
      stb_decode(path)[0].should be_false
    end
  end

  it "does not decode a PNM, however it is named" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "photo.png")
      File.write(path, "P6\n2 2\n255\n".to_slice + Bytes.new(12, 0x55_u8))
      stb_decode(path)[0].should be_false
    end
  end

  it "does not leak stack bytes through a palette entry the PNG never defines" do
    Dir.mktmpdir do |dir|
      # A 10x10 8-bit palette PNG whose PLTE holds 1 entry while the pixels
      # index entry 2 (nothings/stb 298550ab).
      png = Bytes[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00,
        0x00, 0x00, 0x0A, 0x00, 0x00, 0x00, 0x0A, 0x08, 0x03, 0x00, 0x00, 0x00, 0xBA, 0xEC, 0x3F, 0x8F, 0x00,
        0x00, 0x00, 0x03, 0x50, 0x4C, 0x54, 0x45, 0x00, 0x00, 0x00, 0xA7, 0x7A, 0x3D, 0xDA, 0x00, 0x00, 0x00,
        0x11, 0x49, 0x44, 0x41, 0x54, 0x78, 0xDA, 0x63, 0x60, 0x00, 0x81, 0x14, 0x10, 0x60, 0xA0, 0x3D, 0x13,
        0x00, 0x02, 0x0E, 0x13, 0x89, 0x61, 0xBE, 0x38, 0x07, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
        0xAE, 0x42, 0x60, 0x82,
      ]
      path = File.join(dir, "pal.png")
      File.write(path, png)
      dirty_stack
      w = uninitialized LibC::Int
      h = uninitialized LibC::Int
      c = uninitialized LibC::Int
      pixels = LibStb.stbi_load(path, pointerof(w), pointerof(h), pointerof(c), 0)
      pixels.null?.should be_false
      begin
        Slice.new(pixels, w * h * c).count { |b| b != 0 }.should eq 0
      ensure
        LibStb.stbi_image_free(pixels.as(Void*))
      end
    end
  end
end
