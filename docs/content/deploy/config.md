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

`max_deletes` bounds the **built-in** `file://` sync only. Command targets
(`s3://`, `gs://`, `az://`, or an explicit `command`) delete through the
external tool's own flags, which hwaro cannot count in advance.

A deploy also refuses outright when the source directory is empty, or when
`include`/`exclude` selected no files while the destination still holds
some — that combination is almost always "the site was never built" and
would otherwise wipe the destination. Pass `--force` to clear a destination
on purpose.

`workers` is accepted for forward compatibility but not applied: the
built-in sync copies serially and command targets manage their own
concurrency. Setting it prints a warning.

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

A value that starts with a URL scheme is never treated as a local path, so a
single-slash typo (`s3:/bucket`) fails with an unsupported-scheme error
instead of quietly creating a directory named `s3:`. `include`, `exclude`,
and `strip_index_html` apply to the built-in `file://` sync only; on
command targets they warn, because the external tool receives the whole
source tree.

**Local directory sync and symlinks.** The built-in sync keeps every write
inside the destination. A symlink standing where a file or directory belongs
is replaced with the real thing, and a symlink with no counterpart in the
source is unlinked — neither case reads or deletes through the link, so
content living outside the destination is never touched.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| name | string | — | Target identifier (must be unique — duplicates are warned about and only the first is used) |
| url | string | — | Destination URL (`file://`, `s3://`, `gs://`, `az://`) |
| path | string | — | Alias for `url` when deploying to a local directory (`path = "~/public"`; `~` is expanded) |
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
