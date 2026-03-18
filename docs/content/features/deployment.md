+++
title = "Deployment"
description = "Configure deploy targets for hwaro deploy"
weight = 24
+++

Configure deployment targets to publish your site with `hwaro deploy`.

## Configuration

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
url = "file://./out"

[[deployment.targets]]
name = "staging"
url = "file://./staging-out"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| name | string | — | Target identifier |
| url | string | — | Destination URL |
| include | string | — | Glob pattern for files to include |
| exclude | string | — | Glob pattern for files to exclude |
| strip_index_html | bool | false | Remove `index.html` from URLs |
| command | string | — | Custom command to execute for deployment |

### Local Filesystem

Sync to a local directory:

```toml
[[deployment.targets]]
name = "local"
url = "file://./out"
```

### Custom Commands

Use external tools (AWS CLI, gsutil, rsync, etc.) with placeholder variables:

```toml
[[deployment.targets]]
name = "s3"
url = "s3://my-bucket"
command = "aws s3 sync {source}/ {url} --delete"

[[deployment.targets]]
name = "rsync"
url = "user@server:/var/www/site"
command = "rsync -avz --delete {source}/ {url}"
```

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

## Usage

Deploy to the default target:

```bash
hwaro deploy
```

Deploy to a specific target:

```bash
hwaro deploy --target staging
```

Preview without making changes:

```bash
hwaro deploy --dry-run
```
