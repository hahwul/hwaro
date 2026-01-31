+++
title = "Troubleshooting"
description = "Solutions for common issues and errors when using Hwaro."
toc = true
+++

This guide provides solutions for common issues you might encounter while using Hwaro.

## Installation Issues

### Crystal Version Mismatch
Hwaro requires Crystal version 1.10 or higher. If you encounter compilation errors when building from source, check your Crystal version:

```bash
crystal --version
```

If your version is outdated, please update Crystal following the [official installation guide](https://crystal-lang.org/install/).

### Missing Shards
If you see errors about missing dependencies, ensure you have installed the required shards:

```bash
shards install
```

## Build Failures

### Template Not Found
If Hwaro cannot find a template specified in your front matter or the default `page` template, it will issue a warning and might fallback to raw content.

**Solution:**
- Ensure your templates are located in the `templates/` directory.
- Check that the template name in your front matter matches the filename (without extension) in `templates/`.
- Verify you have at least a `page.html` or `default.html` template.

### Markdown Parsing Errors
If your Markdown file has malformed TOML front matter, Hwaro might fail to parse the page correctly.

**Solution:**
- Ensure the front matter is enclosed in `+++` markers.
- Verify the TOML syntax is correct.
- Check the console output for specific error messages and line numbers.

### Pre-build Hook Failures
If you have configured pre-build hooks in `config.toml` and they return a non-zero exit code, the build will be aborted.

**Solution:**
- Check the output of your hook scripts for errors.
- Ensure all necessary tools for the hooks are installed in your environment.

## Content Issues

### Changes Not Reflected
If you make changes to your content or templates but don't see them in the output, it might be due to the build cache.

**Solution:**
- Run the build without caching: `hwaro build` (caching is disabled by default unless `--cache` is used).
- If you were using `--cache`, try deleting the `.hwaro_cache.json` file in your project root.
- Clear your browser cache or use an Incognito/Private window.

### Pages Missing from Output
If some of your Markdown files are not being generated as HTML:

**Solution:**
- Check if the page is marked as a draft: `draft = true` in front matter. Drafts are not built unless you use the `--drafts` flag.
- Verify the file extension is `.md`.
- Ensure the file is located within the `content/` directory.

## Template Errors

### Crinja/Jinja2 Syntax Errors
Hwaro uses the Crinja engine for templating. Syntax errors in your templates will cause build warnings or failures.

**Solution:**
- Check the build logs for `[WARN] Template error` messages.
- Ensure your Jinja2 syntax is correct (e.g., matching `{% ... %}` and `{{ ... }}` tags).
- Verify that variables you are using are available in the [template context](/templates/).

## Deployment Issues

### Broken Links or Missing Assets
If your site looks correct locally but is broken after deployment (e.g., on GitHub Pages):

**Solution:**
- Check your `base_url` setting in `config.toml`. It should match the root URL where your site is hosted.
- If hosting on a subpath (like `https://user.github.io/project/`), set `base_url = "/project"`.
- Use the `{{ base_url }}` variable in your templates for links and assets.

## Getting Help
If you're still having trouble:
- Check the [GitHub Issues](https://github.com/hahwul/hwaro/issues) for similar problems.
- Start a [Discussion](https://github.com/hahwul/hwaro/discussions) on GitHub.
- Review the [documentation](/getting-started/) again to ensure everything is set up correctly.
