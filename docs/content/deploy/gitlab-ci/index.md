+++
title = "GitLab CI"
weight = 4
+++

Deploy your Hwaro site using GitLab CI/CD.

## Configuration

Add `.gitlab-ci.yml` to your repository:

```yaml
image: ghcr.io/hahwul/hwaro:latest

pages:
  script:
    - hwaro build --minify
  artifacts:
    paths:
      - public
  only:
    - main
```

This configuration uses the official Hwaro Docker image to build your site and deploys the `public` directory to GitLab Pages.
