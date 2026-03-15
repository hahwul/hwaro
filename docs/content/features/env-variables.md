+++
title = "Environment Variables"
description = "Reference environment variables in configuration files and templates"
weight = 15
toc = true
+++

Hwaro supports environment variable substitution in both `config.toml` and templates, enabling dynamic configuration for CI/CD pipelines, secret management, and per-developer settings.

## Config Substitution

Environment variables in `config.toml` are resolved before TOML parsing.

### Syntax

| Pattern | Description |
|---------|-------------|
| `${VAR}` | Replace with the value of `VAR` |
| `$VAR` | Same (bare form) |
| `${VAR:-default}` | Use `default` if `VAR` is unset or empty |

### Examples

```toml
# Dynamic base URL for CI/CD
base_url = "${SITE_URL:-https://localhost:1313}"

# Bare form
title = "$SITE_TITLE"

# Default values
description = "${SITE_DESC:-My awesome site}"

[og]
fb_app_id = "${FB_APP_ID:-}"
```

Missing variables without a default value are left unchanged and produce a build-time warning:

```
WARN: Environment variable 'SITE_URL' is not set (referenced in config.toml)
```

## Template Function

Use the `env()` function to read environment variables inside templates.

```jinja
{{ env("ANALYTICS_ID") }}
{{ env("API_KEY", default="none") }}
```

| Parameter | Type | Description |
|-----------|------|-------------|
| name | String | Variable name |
| default | String? | Fallback if unset (optional) |

If the variable is not set and no default is provided, an empty string is returned and a warning is logged.

### Examples

**Conditional analytics snippet:**

```jinja
{% if env("GA_ID") %}
<script async src="https://www.googletagmanager.com/gtag/js?id={{ env("GA_ID") }}"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', '{{ env("GA_ID") }}');
</script>
{% endif %}
```

**API endpoint with fallback:**

```jinja
<script>
  const API_URL = "{{ env("API_URL", default="https://api.example.com") }}";
</script>
```

## Use Cases

### CI/CD Pipelines

Set the base URL per deployment environment:

```bash
SITE_URL=https://staging.example.com hwaro build
SITE_URL=https://example.com hwaro build
```

### Secret Management

Keep API keys and tracking IDs out of version control:

```toml
# config.toml
[og]
fb_app_id = "${FB_APP_ID}"
```

```bash
export FB_APP_ID="123456789"
hwaro build
```

### Per-Developer Settings

Each developer can override values locally via their shell environment without modifying `config.toml`:

```bash
export SITE_URL="http://localhost:1313"
hwaro serve
```

## See Also

- [Configuration](/start/config/) — Full config reference
- [Functions](/templates/functions/) — All template functions
