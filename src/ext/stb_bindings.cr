# Crystal C bindings for stb image libraries
#
# Links against stb_impl.c which provides:
# - stb_image.h        (decode JPG/PNG/BMP/GIF/TGA/PSD/HDR/PIC)
# - stb_image_write.h  (encode JPG/PNG/BMP)
# - stb_image_resize2.h (high-quality resize)
# - stb_truetype.h     (TrueType font rasterization)
#
# The ldflags backtick command auto-compiles stb_impl.o when missing or stale.
# It checks all source files (.c and .h) so header updates trigger a rebuild.

@[Link(ldflags: "`sh -c 'D=#{__DIR__}; OBJ=$D/stb_impl.o; STALE=0; if [ ! -f \"$OBJ\" ]; then STALE=1; else for f in $D/stb_impl.c $D/stb_image.h $D/stb_image_write.h $D/stb_image_resize2.h $D/stb_truetype.h; do [ \"$f\" -nt \"$OBJ\" ] && STALE=1; done; fi; [ $STALE -eq 1 ] && ${CC:-cc} -c -O2 -o \"$OBJ\" \"$D/stb_impl.c\"; echo \"$OBJ\"'`")]
lib LibStb
  # --- stb_image ---
  fun stbi_load(filename : LibC::Char*, x : LibC::Int*, y : LibC::Int*, channels_in_file : LibC::Int*, desired_channels : LibC::Int) : UInt8*
  fun stbi_image_free(retval_from_stbi_load : Void*)
  fun stbi_failure_reason : LibC::Char*

  # --- stb_image_write ---
  fun stbi_write_png(filename : LibC::Char*, w : LibC::Int, h : LibC::Int, comp : LibC::Int, data : Void*, stride_in_bytes : LibC::Int) : LibC::Int
  fun stbi_write_jpg(filename : LibC::Char*, w : LibC::Int, h : LibC::Int, comp : LibC::Int, data : Void*, quality : LibC::Int) : LibC::Int
  fun stbi_write_bmp(filename : LibC::Char*, w : LibC::Int, h : LibC::Int, comp : LibC::Int, data : Void*) : LibC::Int

  # --- stb_image_write (in-memory JPEG for LQIP) ---
  fun hwaro_write_jpg_to_mem(pixels : UInt8*, w : LibC::Int, h : LibC::Int, comp : LibC::Int,
                             quality : LibC::Int, out_buf : UInt8**, out_len : LibC::Int*) : LibC::Int

  # --- stb_image_resize2 ---
  fun stbir_resize_uint8_linear(input_pixels : UInt8*, input_w : LibC::Int, input_h : LibC::Int, input_stride_in_bytes : LibC::Int, output_pixels : UInt8*, output_w : LibC::Int, output_h : LibC::Int, output_stride_in_bytes : LibC::Int, num_channels : LibC::Int) : UInt8*

  # --- stb_truetype (via hwaro C wrappers) ---
  # Font info is an opaque pointer managed by hwaro_font_alloc/free
  type HwaroFontInfo = Void*

  fun hwaro_font_alloc : HwaroFontInfo
  fun hwaro_font_free(info : HwaroFontInfo)
  fun hwaro_font_init(info : HwaroFontInfo, data : UInt8*, offset : LibC::Int) : LibC::Int
  fun hwaro_font_scale_for_pixel_height(info : HwaroFontInfo, pixels : LibC::Float) : LibC::Float
  fun hwaro_font_get_vmetrics(info : HwaroFontInfo, ascent : LibC::Int*, descent : LibC::Int*, line_gap : LibC::Int*)
  fun hwaro_font_get_codepoint_hmetrics(info : HwaroFontInfo, codepoint : LibC::Int, advance_width : LibC::Int*, left_side_bearing : LibC::Int*)
  fun hwaro_font_get_codepoint_kern_advance(info : HwaroFontInfo, ch1 : LibC::Int, ch2 : LibC::Int) : LibC::Int
  fun hwaro_font_get_codepoint_bitmap(info : HwaroFontInfo, scale_x : LibC::Float, scale_y : LibC::Float, codepoint : LibC::Int, width : LibC::Int*, height : LibC::Int*, xoff : LibC::Int*, yoff : LibC::Int*) : UInt8*
  fun hwaro_font_free_bitmap(bitmap : UInt8*)
  fun hwaro_font_measure_text(info : HwaroFontInfo, text : LibC::Char*, scale : LibC::Float) : LibC::Float
  fun hwaro_font_render_text(info : HwaroFontInfo, pixels : UInt8*, buf_w : LibC::Int, buf_h : LibC::Int, x : LibC::Float, y : LibC::Float, scale : LibC::Float, text : LibC::Char*, color : LibC::UInt, opacity : LibC::Float) : LibC::Float
end
