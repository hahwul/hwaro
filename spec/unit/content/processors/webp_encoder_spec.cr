require "../../../spec_helper"
require "../../../../src/content/processors/webp_encoder"
require "../../../../src/content/processors/image_processor"

# The reconstruction the encoder predicts from, for comparing against what a
# real decoder produces.
class Hwaro::Content::Processors::WebpEncoder::VP8
  getter rec_y, rec_u, rec_v, yw, uvw
end

private alias Webp = Hwaro::Content::Processors::WebpEncoder

# A deterministic test picture: gradients plus a hard edge, so every
# predictor and token category gets exercised. Alpha (when present) is a
# horizontal ramp with a fully transparent stripe.
private def picture(width : Int32, height : Int32, channels : Int32) : Bytes
  Bytes.new(width * height * channels) do |i|
    p, c = i.divmod(channels)
    x, y = p % width, p // width
    if (channels == 2 || channels == 4) && c == channels - 1
      next 0_u8 if y < 3
      next (x * 255 // Math.max(width - 1, 1)).to_u8
    end
    edge = x > width // 2 ? 90 : 0
    ((x * 7 + y * (c + 3) * 5 + edge + (x * y) % 13) % 256).to_u8
  end
end

private def chunk_tags(data : Bytes) : Array(String)
  tags = [] of String
  pos = 12
  while pos + 8 <= data.size
    tags << String.new(data[pos, 4])
    size = IO::ByteFormat::LittleEndian.decode(UInt32, data[pos + 4, 4]).to_i32
    pos += 8 + size + (size & 1)
  end
  tags
end

private def riff_vp8(frame : Bytes) : Bytes
  io = IO::Memory.new
  io << "RIFF"
  io.write_bytes((12 + frame.size + (frame.size & 1)).to_u32, IO::ByteFormat::LittleEndian)
  io << "WEBP" << "VP8 "
  io.write_bytes(frame.size.to_u32, IO::ByteFormat::LittleEndian)
  io.write(frame)
  io.write_byte(0_u8) if frame.size.odd?
  io.to_slice
end

private def dwebp(*args : String) : Nil
  status = Process.run("dwebp", ["-quiet"] + args.to_a, output: Process::Redirect::Close, error: Process::Redirect::Close)
  raise "dwebp #{args.join(" ")} failed" unless status.success?
end

# RGBA samples of a decoded PAM file.
private def pam_pixels(path : String) : Bytes
  data = File.read(path).to_slice
  header = String.new(data[0, Math.min(200, data.size)])
  start = header.index!("ENDHDR\n") + 7
  data[start, data.size - start]
end

describe Hwaro::Content::Processors::WebpEncoder do
  it "writes a simple lossy file for opaque pixels" do
    data = Webp.encode(picture(40, 30, 3), 40, 30, 3, 85).not_nil!
    String.new(data[0, 4]).should eq("RIFF")
    String.new(data[8, 4]).should eq("WEBP")
    IO::ByteFormat::LittleEndian.decode(UInt32, data[4, 4]).should eq(data.size - 8)
    chunk_tags(data).should eq(["VP8 "])
  end

  it "stores alpha in an ALPH chunk next to the lossy frame" do
    chunk_tags(Webp.encode(picture(40, 30, 4), 40, 30, 4, 85).not_nil!).should eq(["VP8X", "ALPH", "VP8 "])
  end

  it "drops an alpha channel that is opaque everywhere" do
    pixels = picture(20, 20, 4)
    (0...400).each { |i| pixels[i * 4 + 3] = 255_u8 }
    chunk_tags(Webp.encode(pixels, 20, 20, 4, 85).not_nil!).should eq(["VP8 "])
  end

  it "writes lossless VP8L at quality 100" do
    chunk_tags(Webp.encode(picture(40, 30, 4), 40, 30, 4, 100).not_nil!).should eq(["VP8L"])
  end

  it "records the canvas size every header form is measured by" do
    Dir.mktmpdir do |dir|
      { {3, 85}, {4, 85}, {4, 100}, {1, 50} }.each do |(channels, quality)|
        path = File.join(dir, "c#{channels}q#{quality}.webp")
        File.write(path, Webp.encode(picture(33, 17, channels), 33, 17, channels, quality).not_nil!)
        Hwaro::Content::Processors::ImageProcessor.dimensions(path).should eq({33, 17})
      end
    end
  end

  it "is deterministic" do
    pixels = picture(50, 40, 4)
    Webp.encode(pixels, 50, 40, 4, 75).should eq(Webp.encode(pixels, 50, 40, 4, 75))
  end

  it "refuses sizes outside WebP's canvas range and short buffers" do
    Webp.encode(Bytes.new(3), 0, 1, 3, 85).should be_nil
    Webp.encode(Bytes.new(3), 16384, 1, 3, 85).should be_nil
    Webp.encode(Bytes.new(2), 1, 1, 3, 85).should be_nil
  end

  describe "against libwebp's decoder" do
    sizes = { {1, 1}, {17, 1}, {15, 15}, {33, 47} }

    it "decodes lossy frames to exactly the pixels the encoder predicted from" do
      pending!("dwebp not installed") unless Process.find_executable("dwebp")
      Dir.mktmpdir do |dir|
        sizes.each do |(w, h)|
          {1, 3, 4}.each do |channels|
            {1, 50, 90}.each do |quality|
              enc = Webp::VP8.new(picture(w, h, channels), w, h, channels, quality)
              File.write(File.join(dir, "f.webp"), riff_vp8(enc.encode.not_nil!))
              # -nofilter: the loop filter runs after reconstruction.
              dwebp("-nofilter", File.join(dir, "f.webp"), "-yuv", "-o", File.join(dir, "f.yuv"))
              yuv = File.read(File.join(dir, "f.yuv")).to_slice
              uw, uh = (w + 1) // 2, (h + 1) // 2
              decoded_y = Bytes.new(w * h) { |i| yuv[i] }
              expected_y = Bytes.new(w * h) { |i| enc.rec_y[(i // w) * enc.yw + i % w] }
              decoded_y.should eq(expected_y)
              (uw * uh).times do |i|
                at = (i // uw) * enc.uvw + i % uw
                yuv[w * h + i].should eq(enc.rec_u[at])
                yuv[w * h + uw * uh + i].should eq(enc.rec_v[at])
              end
            end
          end
        end
      end
    end

    it "round-trips alpha and lossless pixels exactly" do
      pending!("dwebp not installed") unless Process.find_executable("dwebp")
      Dir.mktmpdir do |dir|
        sizes.each do |(w, h)|
          {2, 3, 4}.each do |channels|
            pixels = picture(w, h, channels)
            {85, 100}.each do |quality|
              File.write(File.join(dir, "a.webp"), Webp.encode(pixels, w, h, channels, quality).not_nil!)
              dwebp(File.join(dir, "a.webp"), "-pam", "-o", File.join(dir, "a.pam"))
              rgba = pam_pixels(File.join(dir, "a.pam"))
              (w * h).times do |i|
                alpha = channels.even? ? pixels[i * channels + channels - 1] : 255_u8
                rgba[i * 4 + 3].should eq(alpha)
                next unless quality == 100
                3.times { |c| rgba[i * 4 + c].should eq(pixels[i * channels + (channels >= 3 ? c : 0)]) }
              end
            end
          end
        end
      end
    end
  end
end
