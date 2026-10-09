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
content living outside the destination is never touched. Symlinks inside the
source are followed: a real directory and each alias of it (`latest -> v2`)
are all deployed. On a case-insensitive destination, a page that was only
renamed by case (`Docs/Intro.html` to `docs/intro.html`) is updated in place,
not deleted.

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

**Command targets** run through `sh` (`cmd.exe` on Windows). Their output streams as the tool runs,
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

On Windows the command runs through `cmd.exe` instead of `sh`. Placeholder
values are double-quoted, since `cmd.exe` has no single quotes, and
`{source}` uses `\` separators. `cmd.exe` still expands `%NAME%` inside
double quotes, so `%` and `^` count as metacharacters there too.

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
is never deleted as stale. Only a destination file that opens like HTML is
read as a stripped page, so a hand-placed `CNAME` or a stale `img/logo.png` is
judged by its own name alone, while a dotted slug such as `docs/v1.2` still
gets both readings. A name with an extension must also start with a doctype or
`<html>`, so `logo.svg`, `feed.xml` and hand-placed `about.html` files are
never read as stripped pages.

## Matchers

Configure per-file deployment settings using pattern matchers:

```toml
[[deployment.matchers]]
pattern = "^.+\\.html$"
cache_control = "max-age=0, no-cache"
gzip = true

[[deployment.matchers]]
pattern = "^assets/.+\\.(css|js)$"
cache_control = "max-age=31536000, immutable"
force = true
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| pattern | string | — | Regex matched against the source-relative path and the destination name (they differ under `strip_index_html`) |
| force | bool | false | Always copy matched files, even when identical at the destination |
| cache_control | string | — | `Cache-Control` header for matched files (cloud targets) |
| content_type | string | — | `Content-Type` header for matched files (cloud targets) |
| gzip | bool | — | Upload gzip-compressed with `Content-Encoding: gzip` (cloud), or write a `.gz` sibling (local) |

`force` is honored by every matcher whose pattern matches. For the
metadata keys (`cache_control`, `content_type`, `gzip`), the **first**
matcher in config order that sets any of them and matches the file wins,
and it supplies all three. Matchers are not merged, so put specific
patterns before general ones. An explicit `gzip = false` counts as set, so
it opts a path out of a later, broader gzip matcher:

```toml
[[deployment.matchers]]
pattern = "\\.(png|jpg|woff2)$"
gzip = false

[[deployment.matchers]]
pattern = ".*"
gzip = true
```

### Cloud targets (`s3://`, `gs://`, `az://`)

After the main sync, each matched file is uploaded again with its headers,
using the cloud CLI's own flags:

| Target | Command |
|--------|---------|
| `s3://` | `aws s3 cp FILE s3://… --cache-control … --content-type … --content-encoding gzip` |
| `gs://` | `gsutil -h "Cache-Control:…" -h "Content-Type:…" cp -Z FILE gs://…` |
| `az://` | `az storage blob upload --container-name … --file FILE --name … --overwrite --content-cache-control … --content-type … --content-encoding gzip` |

With `gzip = true`, `gsutil -Z` compresses on its own. For `aws` and `az`,
hwaro compresses the file into a temporary copy with the same name and
uploads that. `--dry-run` lists the planned uploads, and `--dry-run --json`
adds an `upload` op per file with a `headers` object. Matched files are
re-uploaded on every deploy.

`gsutil cp` reads `[`, `]`, `*` and `?` in a file name as wildcards, and
has no way to escape them. On `gs://` targets, a matched file whose path
contains one of them is skipped with a warning (it is still deployed by the
main sync, without the extra headers). If the source directory's own path
contains one of them, the target's metadata uploads are skipped with one
warning.

### Local directory targets (`file://`, `path`)

`gzip = true` writes a precompressed `<file>.gz` next to each matched file,
for nginx `gzip_static` or Caddy `precompressed`. A sibling is rewritten
only when it is missing or older than its file. If the source already ships
a `<file>.gz`, that file is deployed unchanged. Siblings are never deleted
as stale while their file is deployed. When a page is removed, its sibling
is deleted with it (even when `include` does not match `*.gz`) and does not
count toward `max_deletes`. Any other `.gz`
file at the destination counts as usual. hwaro keeps no record of the files
it wrote, so this is a heuristic: any `X.gz` deleted together with a
gzip-matched `X` is exempt, even if another tool wrote the pair. A sibling the target's `exclude`
matches is never written. `--dry-run --json` lists each sibling to write as a
`gzip` op whose `source` is the destination file being compressed.

A local copy has no HTTP headers, so `cache_control` and `content_type`
print a warning there. Set those in your web server.

### Custom `command` targets

Matchers are not applied to a target with an explicit `command`; setting
metadata keys prints a warning. Pass headers in the command itself.

## See Also

- [CLI Reference](/start/cli/) — All deploy command-line options
- [Features: Deployment](/features/deployment/) — Quick overview
