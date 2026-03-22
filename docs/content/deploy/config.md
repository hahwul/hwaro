+++
title = "Deploy Configuration"
description = "Configure deployment targets, matchers, and options"
weight = 1
toc = true
+++

Configure deployment targets for the `hwaro deploy` command in `config.toml`.

## Global Options

```toml
[deployment]
target = "prod"
source_dir = "public"
confirm = false
dry_run = false
max_deletes = 256
workers = 10
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| target | string | — | Default target name to deploy to |
| source_dir | string | "public" | Directory containing the built site |
| confirm | bool | false | Prompt for confirmation before deploying |
| dry_run | bool | false | Show what would be deployed without making changes |
| force | bool | false | Force deployment even if no changes detected |
| max_deletes | int | 256 | Safety limit on file deletions (-1 disables the limit) |
| workers | int | 10 | Number of concurrent workers |

## Targets

Define one or more deployment targets:

```toml
[[deployment.targets]]
name = "prod"
url = "file:///var/www/mysite"

[[deployment.targets]]
name = "s3"
url = "s3://my-bucket"
# Auto-generates: aws s3 sync {source}/ s3://my-bucket --delete

[[deployment.targets]]
name = "custom"
url = "s3://my-bucket"
command = "aws s3 sync {source}/ {url} --delete --exclude '.git/*'"
# Custom command overrides auto-generation
```

**Auto-generated commands by URL scheme:**

| Scheme | Command | Requires |
|--------|---------|----------|
| `file://` | Built-in directory sync | — |
| `s3://` | `aws s3 sync {source}/ {url} --delete` | AWS CLI |
| `gs://` | `gsutil -m rsync -r -d {source}/ {url}` | Google Cloud SDK |
| `az://` | `az storage blob sync --source {source} --container {url}` | Azure CLI |

If a `command` field is set, it always takes priority over auto-generation.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| name | string | — | Target identifier |
| url | string | — | Destination URL (`file://`, `s3://`, `gs://`, `az://`) |
| include | string | — | Glob pattern for files to include |
| exclude | string | — | Glob pattern for files to exclude |
| strip_index_html | bool | false | Remove `index.html` from URLs |
| command | string | — | Custom command (overrides auto-generation) |

Custom commands support placeholders:

| Placeholder | Description |
|-------------|-------------|
| `{source}` | Source directory (default: `public`) |
| `{url}` | Target URL |
| `{target}` | Target name |

## Matchers

Configure per-file deployment settings using pattern matchers:

```toml
[[deployment.matchers]]
pattern = "^.+\\.css$"
cache_control = "max-age=31536000"
gzip = true

[[deployment.matchers]]
pattern = "^.+\\.html$"
cache_control = "max-age=3600"
gzip = true
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| pattern | string | — | Regex pattern to match file paths |
| cache_control | string | — | Cache-Control header value |
| content_type | string | — | Override Content-Type header |
| gzip | bool | false | Gzip compress matched files |
| force | bool | false | Always upload matched files |

## See Also

- [CLI Reference](/start/cli/) — All deploy command-line options
- [Features: Deployment](/features/deployment/) — Quick overview
