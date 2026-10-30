+++
title = "ci (deprecated)"
description = "Generate CI/CD workflow files (deprecated, use tool platform)"
weight = 6
+++

> **Deprecated:** `hwaro tool ci` has been merged into `hwaro tool platform`. Use `hwaro tool platform github-pages` instead.

```bash
# Old (deprecated)
hwaro tool ci github-actions

# New
hwaro tool platform github-pages
```

`tool ci github-actions` still writes the same workflow as `tool platform github-pages`
(`.github/workflows/deploy.yml`) and accepts the same `-o, --output PATH`,
`--stdout` and `-f, --force` flags, after printing a deprecation warning on
stderr.

See [platform](/start/tools/platform/) for full documentation.
