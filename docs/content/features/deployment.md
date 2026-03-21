+++
title = "Deployment"
description = "Configure deploy targets for hwaro deploy"
weight = 24
+++

Hwaro includes a built-in `hwaro deploy` command that syncs your built site to configured targets — local directories, S3, or any tool via custom commands.

```toml
[deployment]
source_dir = "public"

[[deployment.targets]]
name = "prod"
url = "file:///var/www/mysite"

[[deployment.targets]]
name = "s3"
url = "s3://my-bucket"
command = "aws s3 sync {source}/ {url} --delete"
```

```bash
hwaro deploy              # Deploy to default target
hwaro deploy --target s3  # Deploy to specific target
hwaro deploy --dry-run    # Preview changes
```

For full configuration (targets, matchers, options) and platform-specific guides, see the [Deploy](/deploy/) section.
