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
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| target | string | — | Default target name to deploy to |
| source_dir | string | "public" | Directory containing the built site |
| confirm | bool | false | Prompt for confirmation before deploying |
| dry_run | bool | false | Show what would be deployed without making changes |
| force | bool | false | Force deployment even if no changes detected |
| max_deletes | int | 256 | Safety limit on file deletions (any negative value disables the limit) |

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
| `az://` | `az storage blob sync --source {source} --container <container> [--destination <path>]` | Azure CLI |

For `az://container/sub/dir` URLs the path becomes the `--destination` prefix inside the container.

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
pattern = "^.+\\.html$"
force = true
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| pattern | string | — | Regex pattern to match file paths |
| force | bool | false | Always copy matched files, even when identical at the destination |
| cache_control | string | — | Reserved — not applied by the built-in sync (see below) |
| content_type | string | — | Reserved — not applied by the built-in sync (see below) |
| gzip | bool | false | Reserved — not applied by the built-in sync (see below) |

The built-in sync copies files and runs external CLIs; it does not talk to
an object-store API, so it can only honor `force`. Setting `cache_control`,
`content_type`, or `gzip` prints a warning — configure headers and
compression at your host or CDN instead.

## See Also

- [CLI Reference](/start/cli/) — All deploy command-line options
- [Features: Deployment](/features/deployment/) — Quick overview
