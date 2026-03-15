+++
title = "Environment-Specific Configuration"
description = "Override config settings per deployment environment"
weight = 16
toc = true
+++

Hwaro supports environment-specific config overrides, allowing different settings for development, staging, and production.

## How It Works

1. Base config is loaded from `config.toml`
2. If an environment is specified, `config.<env>.toml` is loaded and merged on top
3. Nested sections (tables) are deep-merged; top-level and leaf values are replaced

## Setting the Environment

Use the `--env` flag or the `HWARO_ENV` environment variable:

```bash
# Via CLI flag
hwaro build --env production
hwaro serve --env development

# Via environment variable
HWARO_ENV=staging hwaro build

# CLI flag takes precedence over HWARO_ENV
```

## File Structure

```
mysite/
├── config.toml                  # Base configuration (always loaded)
├── config.development.toml      # Development overrides
├── config.staging.toml          # Staging overrides
└── config.production.toml       # Production overrides
```

## Example

**config.toml** (base):

```toml
title = "My Blog"
base_url = "http://localhost:3000"

[sitemap]
enabled = true
changefreq = "weekly"

[search]
enabled = true
```

**config.production.toml** (override):

```toml
base_url = "https://myblog.com"

[sitemap]
changefreq = "daily"
```

Running `hwaro build --env production` produces a config equivalent to:

```toml
title = "My Blog"                     # from base
base_url = "https://myblog.com"       # overridden by production

[sitemap]
enabled = true                        # from base (deep-merged)
changefreq = "daily"                  # overridden by production

[search]
enabled = true                        # from base (untouched)
```

## Deep Merge Behavior

Sub-tables are merged recursively, not replaced entirely. This means you only need to specify the values you want to change:

| Base | Override | Result |
|------|----------|--------|
| `[sitemap] enabled = true, changefreq = "weekly"` | `[sitemap] changefreq = "daily"` | `[sitemap] enabled = true, changefreq = "daily"` |

Top-level scalars and arrays are replaced, not merged:

| Base | Override | Result |
|------|----------|--------|
| `title = "Base"` | `title = "Prod"` | `title = "Prod"` |

## Environment Variables

Environment-specific config files also support [environment variable substitution](/features/env-variables/):

```toml
# config.production.toml
base_url = "${PRODUCTION_URL}"

[og]
fb_app_id = "${FB_APP_ID}"
```

## Use Cases

### Different base URLs per environment

```toml
# config.development.toml
base_url = "http://localhost:3000"

# config.staging.toml
base_url = "https://staging.myblog.com"

# config.production.toml
base_url = "https://myblog.com"
```

### Enable features only in production

```toml
# config.production.toml
[search]
enabled = true

[feeds]
enabled = true
```

### Different analytics per environment

```toml
# config.staging.toml
[og]
fb_app_id = "staging-app-id"

# config.production.toml
[og]
fb_app_id = "prod-app-id"
```

## See Also

- [Configuration](/start/config/) — Full config reference
- [Environment Variables](/features/env-variables/) — Env var substitution in config and templates
- [CLI](/start/cli/) — Command-line options
