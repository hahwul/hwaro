/* stb single-file library implementations for Hwaro image processing
 *
 * Vendored versions (update these when upgrading headers):
 *   stb_image.h        v2.30
 *   stb_image_write.h  v1.16
 *   stb_image_resize2.h v2.18
 *   stb_truetype.h     v1.26
 *
 * Source: https://github.com/nothings/stb
 */

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize2.h"

#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

#include <stdlib.h>
#include <string.h>

/* ---- Thin C wrappers for stb_truetype (opaque pointer for Crystal) ---- */

stbtt_fontinfo *hwaro_font_alloc(void) {
    return (stbtt_fontinfo *)calloc(1, sizeof(stbtt_fontinfo));
}

void hwaro_font_free(stbtt_fontinfo *info) {
    free(info);
}

int hwaro_font_init(stbtt_fontinfo *info, const unsigned char *data, int font_index) {
    /* For TTC (TrueType Collection) files, we need to resolve the actual
       byte offset from the font index. stbtt_GetFontOffsetForIndex handles
       both TTC and plain TTF files correctly (returns 0 for plain TTF). */
    int offset = stbtt_GetFontOffsetForIndex(data, font_index);
    if (offset < 0) return 0;
    return stbtt_InitFont(info, data, offset);
}

float hwaro_font_scale_for_pixel_height(const stbtt_fontinfo *info, float pixels) {
    return stbtt_ScaleForPixelHeight(info, pixels);
}

void hwaro_font_get_vmetrics(const stbtt_fontinfo *info, int *ascent, int *descent, int *line_gap) {
    stbtt_GetFontVMetrics(info, ascent, descent, line_gap);
}

void hwaro_font_get_codepoint_hmetrics(const stbtt_fontinfo *info, int codepoint, int *advance_width, int *left_side_bearing) {
    stbtt_GetCodepointHMetrics(info, codepoint, advance_width, left_side_bearing);
}

int hwaro_font_get_codepoint_kern_advance(const stbtt_fontinfo *info, int ch1, int ch2) {
    return stbtt_GetCodepointKernAdvance(info, ch1, ch2);
}

unsigned char *hwaro_font_get_codepoint_bitmap(const stbtt_fontinfo *info, float scale_x, float scale_y, int codepoint, int *width, int *height, int *xoff, int *yoff) {
    return stbtt_GetCodepointBitmap(info, scale_x, scale_y, codepoint, width, height, xoff, yoff);
}

void hwaro_font_free_bitmap(unsigned char *bitmap) {
    stbtt_FreeBitmap(bitmap, NULL);
}

/* Measure text width in pixels for a given string (UTF-8) at a given scale */
float hwaro_font_measure_text(const stbtt_fontinfo *info, const char *text, float scale) {
    float x = 0;
    int prev_codepoint = 0;
    const char *p = text;
    while (*p) {
        /* Simple UTF-8 decode */
        int codepoint;
        unsigned char c = (unsigned char)*p;
        int bytes;
        if (c < 0x80) { codepoint = c; bytes = 1; }
        else if (c < 0xE0) { codepoint = c & 0x1F; bytes = 2; }
        else if (c < 0xF0) { codepoint = c & 0x0F; bytes = 3; }
        else { codepoint = c & 0x07; bytes = 4; }
        for (int i = 1; i < bytes && p[i]; i++)
            codepoint = (codepoint << 6) | (p[i] & 0x3F);
        p += bytes;

        int advance, lsb;
        stbtt_GetCodepointHMetrics(info, codepoint, &advance, &lsb);
        if (prev_codepoint)
            x += scale * stbtt_GetCodepointKernAdvance(info, prev_codepoint, codepoint);
        x += scale * advance;
        prev_codepoint = codepoint;
    }
    return x;
}

/* Render text onto an RGBA buffer. Color is 0xRRGGBB. Returns final x position. */
float hwaro_font_render_text(const stbtt_fontinfo *info, unsigned char *pixels, int buf_w, int buf_h,
                             float x, float y, float scale, const char *text,
                             unsigned int color, float opacity) {
    int ascent, descent, line_gap;
    stbtt_GetFontVMetrics(info, &ascent, &descent, &line_gap);
    float baseline = y + scale * ascent;

    unsigned char r = (color >> 16) & 0xFF;
    unsigned char g = (color >> 8) & 0xFF;
    unsigned char b = color & 0xFF;

    int prev_codepoint = 0;
    const char *p = text;
    while (*p) {
        /* UTF-8 decode */
        int codepoint;
        unsigned char c = (unsigned char)*p;
        int bytes;
        if (c < 0x80) { codepoint = c; bytes = 1; }
        else if (c < 0xE0) { codepoint = c & 0x1F; bytes = 2; }
        else if (c < 0xF0) { codepoint = c & 0x0F; bytes = 3; }
        else { codepoint = c & 0x07; bytes = 4; }
        for (int i = 1; i < bytes && p[i]; i++)
            codepoint = (codepoint << 6) | (p[i] & 0x3F);
        p += bytes;

        if (prev_codepoint)
            x += scale * stbtt_GetCodepointKernAdvance(info, prev_codepoint, codepoint);

        int gw, gh, xoff, yoff;
        unsigned char *glyph_bmp = stbtt_GetCodepointBitmap(info, scale, scale, codepoint, &gw, &gh, &xoff, &yoff);

        if (glyph_bmp) {
            int bx = (int)(x + xoff);
            int by = (int)(baseline + yoff);
            for (int gy = 0; gy < gh; gy++) {
                int py = by + gy;
                if (py < 0 || py >= buf_h) continue;
                for (int gx = 0; gx < gw; gx++) {
                    int px = bx + gx;
                    if (px < 0 || px >= buf_w) continue;
                    float alpha = (glyph_bmp[gy * gw + gx] / 255.0f) * opacity;
                    if (alpha <= 0) continue;
                    int idx = (py * buf_w + px) * 4;
                    unsigned char dr = pixels[idx];
                    unsigned char dg = pixels[idx + 1];
                    unsigned char db = pixels[idx + 2];
                    unsigned char da = pixels[idx + 3];
                    pixels[idx]     = (unsigned char)(dr + (r - dr) * alpha);
                    pixels[idx + 1] = (unsigned char)(dg + (g - dg) * alpha);
                    pixels[idx + 2] = (unsigned char)(db + (b - db) * alpha);
                    float new_a = da / 255.0f + alpha * (1.0f - da / 255.0f);
                    pixels[idx + 3] = (unsigned char)(new_a * 255);
                }
            }
            stbtt_FreeBitmap(glyph_bmp, NULL);
        }

        int advance, lsb;
        stbtt_GetCodepointHMetrics(info, codepoint, &advance, &lsb);
        x += scale * advance;
        prev_codepoint = codepoint;
    }
    return x;
}

/* ---- In-memory JPEG writer for LQIP ---- */

typedef struct {
    unsigned char *buf;
    int            len;
    int            cap;
    int            failed;
} hwaro_membuf;

static void hwaro_membuf_write(void *context, void *data, int size) {
    hwaro_membuf *mb = (hwaro_membuf *)context;
    if (mb->failed) return;
    if (mb->len + size > mb->cap) {
        int new_cap = mb->cap * 2;
        if (new_cap < mb->len + size) new_cap = mb->len + size;
        unsigned char *new_buf = (unsigned char *)realloc(mb->buf, new_cap);
        if (!new_buf) {
            free(mb->buf);
            mb->buf = NULL;
            mb->len = 0;
            mb->cap = 0;
            mb->failed = 1;
            return;
        }
        mb->buf = new_buf;
        mb->cap = new_cap;
    }
    memcpy(mb->buf + mb->len, data, size);
    mb->len += size;
}

/*
 * Encode pixel data as JPEG into a malloc'd buffer.
 * Caller must free(*out_buf) when done.
 * Returns 1 on success, 0 on failure.
 */
int hwaro_write_jpg_to_mem(const unsigned char *pixels, int w, int h, int comp,
                           int quality, unsigned char **out_buf, int *out_len) {
    hwaro_membuf mb;
    mb.cap = w * h * comp;
    if (mb.cap < 1024) mb.cap = 1024;
    mb.buf = (unsigned char *)malloc(mb.cap);
    mb.len = 0;
    mb.failed = 0;
    if (!mb.buf) {
        *out_buf = NULL;
        *out_len = 0;
        return 0;
    }
    int ok = stbi_write_jpg_to_func(hwaro_membuf_write, &mb, w, h, comp, pixels, quality);
    if (!ok || mb.failed || !mb.buf) {
        free(mb.buf);
        *out_buf = NULL;
        *out_len = 0;
        return 0;
    }
    *out_buf = mb.buf;
    *out_len = mb.len;
    return 1;
}
