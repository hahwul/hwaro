+++
title = "GitLab CI"
description = "Deploy your Hwaro site using GitLab CI/CD"
weight = 3
+++

Deploy your Hwaro site using GitLab CI/CD.

## Configuration

Add `.gitlab-ci.yml` to your repository:

```yaml
image: ghcr.io/hahwul/hwaro:latest

pages:
  script:
    - hwaro build
  artifacts:
    paths:
      - public
  only:
    - main
```

This configuration uses the official Hwaro Docker image to build your site and deploys the `public` directory to GitLab Pages.

## See Also

- [Deploy Configuration](/deploy/config/) — Target setup and matchers
- [CLI Reference](/start/cli/) — All deploy command options
- Other platforms: [GitHub Pages](/deploy/github-pages/) | [Netlify](/deploy/netlify/) | [Vercel](/deploy/vercel/)
