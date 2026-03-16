+++
title = "Image Processing"
description = "Automatic image resizing during build with zero external dependencies"
weight = 21
toc = true
+++

Hwaro can automatically generate resized image variants during build. This is useful for responsive images, thumbnails, and performance optimization. No external tools required — image processing is built into the binary using [stb](https://github.com/nothings/stb) libraries.

## Supported Formats

| Format | Read | Write |
|--------|------|-------|
| JPEG (.jpg, .jpeg) | Yes | Yes |
| PNG (.png) | Yes | Yes |
| BMP (.bmp) | Yes | Yes |

## Configuration

Enable image processing in `config.toml`:

```toml
[image_processing]
enabled = true
widths = [320, 640, 1024, 1280]
quality = 85
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Enable image resizing |
| widths | array | [] | Target widths to generate (in pixels) |
| quality | int | 85 | JPEG output quality (1-100) |

## How It Works

1. During build, Hwaro scans images in three locations:
   - **Page bundle assets** (images colocated with `index.md`)
   - **Content files** (images published via `[content.files]` config)
   - **Static files** (images in the `static/` directory)
2. For each image, resized variants are generated for every configured width
3. Aspect ratio is always preserved
4. If the target width is larger than the source, the original is copied as-is (no upscaling)
5. Each source image is decoded only once, then resized to all widths (efficient)

## Output Naming

Resized images follow the naming convention `{name}_{width}w.{ext}`. For example, with `static/hwaro.png`:

```
static/hwaro.png
  -> public/hwaro_320w.png
  -> public/hwaro_640w.png
  -> public/hwaro_1024w.png
  -> public/hwaro_1280w.png
```

## Using in Templates

Use the `resize_image()` function to get the URL of a resized variant:

```jinja
{% set img = resize_image(path="/hwaro.png", width=640) %}
<img src="{{ img.url }}" width="{{ img.width }}">
```

For responsive images with `srcset`:

```jinja
{% set sm = resize_image(path="/hwaro.png", width=320) %}
{% set md = resize_image(path="/hwaro.png", width=640) %}
{% set lg = resize_image(path="/hwaro.png", width=1024) %}
<img
  src="{{ md.url }}"
  srcset="{{ sm.url }} 320w, {{ md.url }} 640w, {{ lg.url }} 1024w"
  sizes="(max-width: 640px) 320px, (max-width: 1024px) 640px, 1024px"
  alt="Hwaro logo"
>
```

The function selects the closest available width. If you request `width=500` and the configured widths are `[320, 640, 1024]`, it returns the 640px variant (smallest width >= requested). If no variant is large enough, it falls back to the largest available.

## Live Demo

This docs site has image processing enabled with `widths = [128, 256, 512]`. The images below are automatically generated resized variants of `static/hwaro.png`:

**Original** (`hwaro.png`):

<img src="/hwaro.png" alt="Hwaro logo - original" style="max-width:256px">

**128px** (`hwaro_128w.png`):

<img src="/hwaro_128w.png" alt="Hwaro logo - 128px wide">

**256px** (`hwaro_256w.png`):

<img src="/hwaro_256w.png" alt="Hwaro logo - 256px wide">

**512px** (`hwaro_512w.png`):

<img src="/hwaro_512w.png" alt="Hwaro logo - 512px wide">

These files are generated at build time — no runtime resizing or external services needed. In your templates, use `resize_image()` to reference them:

```jinja
{% set img = resize_image(path="/hwaro.png", width=256) %}
<img src="{{ img.url }}">
{# renders as: <img src="/hwaro_256w.png"> #}
```

## Performance

- **Single decode**: Each source image is decoded once and resized to all target widths in memory
- **Parallel processing**: Multiple images are processed concurrently using a worker pool
- **No upscaling**: Images smaller than the target width are simply copied

## Quick Example

Suppose your site has `static/hwaro.png` (the Hwaro logo) and you want to display it as a responsive image:

**config.toml:**

```toml
[image_processing]
enabled = true
widths = [128, 256, 512]
quality = 90
```

**Template:**

```jinja
{% set logo_sm = resize_image(path="/hwaro.png", width=128) %}
{% set logo_md = resize_image(path="/hwaro.png", width=256) %}
{% set logo_lg = resize_image(path="/hwaro.png", width=512) %}
<img
  src="{{ logo_md.url }}"
  srcset="{{ logo_sm.url }} 128w, {{ logo_md.url }} 256w, {{ logo_lg.url }} 512w"
  sizes="(max-width: 480px) 128px, (max-width: 768px) 256px, 512px"
  alt="Hwaro"
>
```

**Build output:**

```
public/
  hwaro.png           (original, copied by static files)
  hwaro_128w.png      (128px wide)
  hwaro_256w.png      (256px wide)
  hwaro_512w.png      (512px wide)
```

## Blog Post Images

For blog posts with a hero image in front matter:

```toml
[image_processing]
enabled = true
widths = [320, 640, 1024]
quality = 85

[content.files]
allow_extensions = ["jpg", "jpeg", "png"]
```

```jinja
{% if page.image %}
  {% set hero = resize_image(path=page.image, width=1024) %}
  {% set thumb = resize_image(path=page.image, width=320) %}
  <picture>
    <source media="(min-width: 768px)" srcset="{{ hero.url }}">
    <img src="{{ thumb.url }}" alt="{{ page.title }}">
  </picture>
{% endif %}
```

## See Also

- [Content Files](/features/content-files/) — Publishing non-Markdown files from content/
- [Auto OG Images](/features/og-images/) — Auto-generated Open Graph preview images
- [Functions](/templates/functions/) — Template function reference
