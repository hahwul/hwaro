+++
title = "GitLab CI"
description = "Deploy your Hwaro site using GitLab CI/CD"
weight = 3
+++

Deploy your Hwaro site using GitLab CI/CD.

## Quick Start

Auto-generate the config file:

```bash
hwaro tool platform gitlab-ci
```

## Configuration

Or add `.gitlab-ci.yml` to your repository manually:

```yaml
image:
  name: ghcr.io/hahwul/hwaro:latest
  entrypoint: [""]

pages:
  stage: deploy
  script:
    - hwaro build
  artifacts:
    paths:
      - public
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

This configuration uses the official Hwaro Docker image to build your site and deploys the `public` directory to GitLab Pages on pushes to the default branch. `entrypoint: [""]` is required: the image's entrypoint passes its arguments to `hwaro`, so without the override GitLab cannot run the job's shell script.

## See Also

- [Deploy Configuration](/deploy/config/) — Target setup and matchers
- [CLI Reference](/start/cli/) — All deploy command options
- Other platforms: [GitHub Pages](/deploy/github-pages/) | [Netlify](/deploy/netlify/) | [Vercel](/deploy/vercel/)
