# Crystal C bindings for stb image libraries
#
# Links against stb_impl.c which provides:
# - stb_image.h      (decode JPG/PNG/BMP/GIF/TGA/PSD/HDR/PIC)
# - stb_image_write.h (encode JPG/PNG/BMP/TGA)
# - stb_image_resize2.h (high-quality resize)

@[Link(ldflags: "`sh -c 'OBJ=#{__DIR__}/stb_impl.o; SRC=#{__DIR__}/stb_impl.c; if [ ! -f \"$OBJ\" ] || [ \"$SRC\" -nt \"$OBJ\" ]; then cc -c -O2 -o \"$OBJ\" \"$SRC\"; fi; echo \"$OBJ\"'`")]
lib LibStb
  # --- stb_image ---
  fun stbi_load(filename : LibC::Char*, x : LibC::Int*, y : LibC::Int*, channels_in_file : LibC::Int*, desired_channels : LibC::Int) : UInt8*
  fun stbi_image_free(retval_from_stbi_load : Void*)

  # --- stb_image_write ---
  fun stbi_write_png(filename : LibC::Char*, w : LibC::Int, h : LibC::Int, comp : LibC::Int, data : Void*, stride_in_bytes : LibC::Int) : LibC::Int
  fun stbi_write_jpg(filename : LibC::Char*, w : LibC::Int, h : LibC::Int, comp : LibC::Int, data : Void*, quality : LibC::Int) : LibC::Int
  fun stbi_write_bmp(filename : LibC::Char*, w : LibC::Int, h : LibC::Int, comp : LibC::Int, data : Void*) : LibC::Int

  # --- stb_image_resize2 ---
  fun stbir_resize_uint8_linear(input_pixels : UInt8*, input_w : LibC::Int, input_h : LibC::Int, input_stride_in_bytes : LibC::Int, output_pixels : UInt8*, output_w : LibC::Int, output_h : LibC::Int, output_stride_in_bytes : LibC::Int, num_channels : LibC::Int) : UInt8*
end
