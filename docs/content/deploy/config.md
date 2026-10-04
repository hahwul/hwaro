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
some. That combination is almost always "the site was never built" and
would otherwise wipe the destination. Pass `--force` to clear a destination
on purpose. A `command` target that never interpolates `{source}` is exempt.

A source directory containing a `.hwaro-dev` marker is refused as well.
That marker means the directory is `hwaro serve` output, with the dev
server's `base_url` (e.g. `http://127.0.0.1:3000`) baked into every link.
Run `hwaro build` and deploy its output instead; there is no override flag
(deleting the marker file by hand is the deliberate escape hatch).

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

On Windows a `file://` URL takes a drive path: `file:///C:/www/site` (or
`file://C:/www/site`). `path = "C:\\www\\site"` works too.

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
source is unlinked. Neither case reads or deletes through the link, so
content living outside the destination is never touched.

**What the sync leaves alone.** At the destination, hidden directories other
than `.well-known/` are never scanned, so nothing in them is deleted, and a
`.git` entry is always kept. A destination that is a `git worktree` or
submodule checkout (the usual gh-pages setup) stays attached to its
repository. On the source side every hidden directory the build wrote is
deployed (`.well-known/`, `.circleci/`, …) except version-control metadata
(`.git/`, `.svn/`, `.hg/`, `.bzr/`). Empty directories are removed only when
the sync's own deletes emptied them; an empty directory it never selected
(say, `uploads/` outside `include`) is kept.

**File ↔ directory swaps.** Turning `strip_index_html` on or off flips each
page between a file `foo` and a directory `foo/` holding `index.html`. When
the entry in the way is stale (everything in it would be deleted anyway), the
sync removes it before copying the new one, and the plan lists it as a
delete. If it holds anything the sync keeps (a hidden directory, a path
outside `include`/`exclude`), the deploy refuses before writing anything.

**Command targets** run through `sh`. Their output streams as the tool runs,
stderr included. On an interactive terminal the tool can read your input (a
login or confirmation prompt); in pipes, CI, `--quiet` and `--json` runs stdin
is closed. The command also gets `HWARO_DEPLOY_TARGET`, `HWARO_DEPLOY_URL` and
`HWARO_DEPLOY_SOURCE` in its environment. Read them from a script the command
runs: config.toml expands `$VAR` and `${VAR}` itself when it is loaded, and
warns about every one that is unset at that point.

Placeholder values are single-quoted, which keeps them one inert word where
the placeholder stands on its own (`rsync -a {source}/ host:`). Do not wrap a
placeholder in quotes of your own (`"{source}"`). That undoes the quoting, so
hwaro checks the expanded value for shell metacharacters and asks for
confirmation when it finds any.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| name | string | — | Target identifier (must be unique; duplicates are warned about and only the first is used) |
| url | string | — | Destination URL (`file://`, `s3://`, `gs://`, `az://`) |
| path | string | — | Alias for `url` when deploying to a local directory (`path = "~/public"`; `~` is expanded) |
| include | string | — | Glob pattern for files to include (see below) |
| exclude | string | — | Glob pattern for files to exclude (see below) |
| strip_index_html | bool | false | Remove `index.html` from URLs |
| command | string | — | Custom command (overrides auto-generation) |

Custom commands support placeholders:

| Placeholder | Description |
|-------------|-------------|
| `{source}` | Source directory (default: `public`) |
| `{url}` | Target URL |
| `{target}` | Target name |

Any other `{name}` token is rejected as a typo before the command runs. A
`{` preceded by `$` is left to the shell.

`include` and `exclude` are globs matched against the path relative to the
source directory, e.g. `blog/post/index.html`. `*` does not cross `/`, so
match any depth with `**/`: `exclude = "**/*.map"` drops source maps
everywhere, while `*.map` only matches at the top level. With
`strip_index_html`, a stripped page `blog/post` is also judged by its source
name `blog/post/index.html`. If either spelling is excluded, the deployed page
is never deleted as stale.

## Matchers

Configure per-file deployment settings using pattern matchers:

```toml
[[deployment.matchers]]
pattern = "^.+\\.html$"
force = true
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| pattern | string | — | Regex matched against the source-relative path and the destination name (they differ under `strip_index_html`) |
| force | bool | false | Always copy matched files, even when identical at the destination |
| cache_control | string | — | Reserved — not applied by the built-in sync (see below) |
| content_type | string | — | Reserved — not applied by the built-in sync (see below) |
| gzip | bool | false | Reserved — not applied by the built-in sync (see below) |

The built-in sync copies files and runs external CLIs; it does not talk to
an object-store API, so it can only honor `force`. Setting `cache_control`,
`content_type`, or `gzip` prints a warning. Configure headers and
compression at your host or CDN instead.

## See Also

- [CLI Reference](/start/cli/) — All deploy command-line options
- [Features: Deployment](/features/deployment/) — Quick overview
