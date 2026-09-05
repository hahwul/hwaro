+++
title = "Build Hooks"
description = "Run custom shell commands before and after the build process"
weight = 15
toc = true
+++

Build hooks allow you to run custom shell commands before and after the build process. This is useful for tasks like installing dependencies, preprocessing data, optimizing assets, or triggering deployments.

## Configuration

Define hooks in `config.toml`:

```toml
[build]
hooks.pre = ["npm install", "npx tsc"]
hooks.post = ["npm run minify", "npx pagefind --site public"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| hooks.pre | array | [] | Commands to run **before** building |
| hooks.post | array | [] | Commands to run **after** building |

## How It Works

### Pre-Build Hooks

Pre-build hooks run **before** any content processing begins. They are ideal for:

- Installing dependencies
- Compiling assets (TypeScript, Tailwind/PostCSS, and so on; SCSS has a [built-in compiler](/features/sass/))
- Running data fetching scripts
- Preprocessing content

```toml
[build]
hooks.pre = [
  "npm ci",
  "npx tailwindcss -i src/input.css -o static/assets/css/main.css",
  "python scripts/fetch-data.py"
]
```

If a pre-build hook **fails** (exits with a non-zero status), the build process is **aborted**. This prevents building with missing dependencies or broken assets.

### Post-Build Hooks

Post-build hooks run **after** the site has been generated in the output directory. They are ideal for:

- Optimizing images
- Minifying assets
- Generating search indexes (e.g., Pagefind)
- Deploying the site
- Running validation checks

```toml
[build]
hooks.post = [
  "npx imagemin public/images/* --out-dir=public/images",
  "npx pagefind --site public",
  "./scripts/deploy.sh"
]
```

If a post-build hook **fails**, a warning is shown but the build is **not** considered failed. The generated site remains intact.

## Execution Order

Commands are executed **sequentially** in the order they are defined:

```toml
[build]
hooks.pre = ["echo Step 1", "echo Step 2", "echo Step 3"]
```

Output:

```
Running pre-build hook: echo Step 1
Step 1
Running pre-build hook: echo Step 2
Step 2
Running pre-build hook: echo Step 3
Step 3
```

## Serve Mode

Build hooks also run during `hwaro serve`, but only on **full** rebuilds:

- Hooks execute on the **initial build** when the server starts
- Hooks **re-execute on full rebuilds**: a `config.toml` change, a file added or removed, or a change to any file under `data/`
- Hooks are **skipped on partial rebuilds**: editing an existing content or template file re-renders only the affected pages and does not re-run your commands
- Config changes are picked up automatically. If you modify `hooks.pre` or `hooks.post` in `config.toml`, the new commands take effect on the next rebuild

This keeps save-to-reload fast. If a hook produces something you need refreshed while the server is running, touch `config.toml` or restart `hwaro serve` to force a full rebuild.

### Rebuild loops

A hook that writes into a watched directory (`content/`, `templates/`, `static/`, `data/`, `i18n/`), or into `config.toml` itself, feeds the watcher its own output. The harmless case is handled for you: when a run lands the **same bytes** the build already read (`curl -o data/team.json` fetching an unchanged payload, a bundler re-emitting an identical file, a hook that only touches `config.toml`), the session settles instead of rebuilding forever. Depending on where the file lives, the rewrite is either ignored outright or absorbed by a partial rebuild that does not re-run your commands.

Two patterns still rebuild on every run, because to the watcher they are genuine changes:

- writing **different** bytes each time: an embedded timestamp, a build counter, a non-deterministic bundle hash
- **creating and deleting** a file under a watched directory on every run

Make the output deterministic, or write it somewhere the watcher does not look (`.hwaro/` is ignored, as is anything outside the directories listed above).

## Use Cases

### TypeScript Compilation

```toml
[build]
hooks.pre = ["npx tsc --outDir static/assets/js"]
```

### Tailwind CSS

```toml
[build]
hooks.pre = [
  "npx tailwindcss -i src/styles.css -o static/assets/css/styles.css --minify"
]
```

### Fetching Data from an API

For the common case, a GET request whose payload should land in `site.data`, you don't need a hook at all. Declare a [`[[data.remote]]` source](/features/remote-data/) in `config.toml` and Hwaro fetches it once per build, with disk caching and explicit error handling built in.

A pre-build hook remains the right tool when the fetch is more than a single request. `load_data()` reads from disk only, so remote data is baked in by fetching it into `data/` before the build. Every file under `data/` is then exposed as `site.data`:

```toml
[build]
hooks.pre = ["curl -sfL https://api.example.com/team -o data/team.json"]
```

```jinja
{% for member in site.data.team %}
  <li>{{ member.name }}</li>
{% endfor %}
```

`curl -f` exits non-zero on an HTTP error, which aborts the build rather than publishing a site with missing data. For anything beyond a single request (pagination, auth headers, reshaping the response), write a script and call that instead:

```toml
[build]
hooks.pre = ["./scripts/fetch-data.sh"]
```

Commit the fetched file if you want reproducible builds offline; add it to `.gitignore` if you always want it fresh.

### Pagefind Search

Generate a client-side search index after build:

```toml
[build]
hooks.post = ["npx pagefind --site public"]
```

### Image Optimization

```toml
[build]
hooks.post = [
  "npx imagemin public/**/*.{jpg,png} --out-dir=public"
]
```

### Custom Deploy Script

```toml
[build]
hooks.post = ["./scripts/deploy.sh"]
```

### Full Pipeline Example

```toml
[build]
hooks.pre = [
  "npm ci",
  "npx tsc",
  "npx tailwindcss -i src/input.css -o static/assets/css/main.css --minify"
]
hooks.post = [
  "npx pagefind --site public",
  "npx imagemin public/images/* --out-dir=public/images",
  "echo 'Build complete!'"
]
```

## Error Handling

| Hook Type | On Failure |
|-----------|------------|
| Pre-build | ❌ Build **aborted** — no content is processed |
| Post-build | ⚠️ Warning shown — generated site is preserved |

This design ensures that critical setup tasks (pre-build) must succeed, while optional optimization tasks (post-build) don't block the build output.

## Tips

- **Keep hooks fast**: Slow hooks run on every full rebuild during `hwaro serve`. Consider caching or conditional execution.
- **Use scripts for complexity**: For multi-step processes, write a shell script and call it from the hook: `hooks.pre = ["./scripts/setup.sh"]`
- **Check dependencies**: Use `command -v` to check if tools are available before running them:
  ```bash
  command -v npx >/dev/null 2>&1 && npx pagefind --site public
  ```
- **Combine with Auto Includes**: Use pre-build hooks to compile CSS/JS, then let [Auto Includes](/features/auto-includes/) pick them up automatically.

## See Also

- [Configuration](/start/config/) — Full configuration reference
- [Auto Includes](/features/auto-includes/) — Automatic CSS/JS loading
- [Search](/features/search/) — Search index with Pagefind post-build hook
- [Deploy](/deploy/) — Deployment options
