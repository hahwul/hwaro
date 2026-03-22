+++
title = "Deployment"
description = "Configure deploy targets for hwaro deploy"
weight = 24
+++

Hwaro includes a built-in `hwaro deploy` command that syncs your built site to configured targets — local directories, cloud storage, or any tool via custom commands.

```toml
[deployment]
source_dir = "public"

[[deployment.targets]]
name = "prod"
url = "file:///var/www/mysite"

[[deployment.targets]]
name = "s3"
url = "s3://my-bucket"
# No command needed — auto-generated from URL scheme (requires aws CLI)

[[deployment.targets]]
name = "gcs"
url = "gs://my-bucket"
# Auto-generated (requires gsutil)
```

**Supported URL schemes:**

| Scheme | Auto Command | Requires |
|--------|-------------|----------|
| `file://` | Local directory sync | — |
| `s3://` | `aws s3 sync` | AWS CLI |
| `gs://` | `gsutil -m rsync` | Google Cloud SDK |
| `az://` | `az storage blob sync` | Azure CLI |

You can always override with a custom `command` field for full control.

```bash
hwaro deploy              # Deploy to default target
hwaro deploy --target s3  # Deploy to specific target
hwaro deploy --dry-run    # Preview changes
```

For full configuration (targets, matchers, options) and platform-specific guides, see the [Deploy](/deploy/) section.
