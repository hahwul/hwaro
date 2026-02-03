+++
title = "Docker"
weight = 3
+++

Deploy your Hwaro site using Docker.

## Official Image

The official Docker image is available at `ghcr.io/hahwul/hwaro`.

```bash
docker pull ghcr.io/hahwul/hwaro:latest
```

## Multi-stage Build

You can use a multi-stage build to compile your site and serve it with a lightweight web server like Nginx.

Create a `Dockerfile` in your project root:

```dockerfile
# Stage 1: Build the site
FROM ghcr.io/hahwul/hwaro:latest AS builder

WORKDIR /site
COPY . .

# Build with production settings
RUN hwaro build --minify

# Stage 2: Serve with Nginx
FROM nginx:alpine

# Copy built assets from builder stage
COPY --from=builder /site/public /usr/share/nginx/html

# Expose port 80
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

### Build and Run

```bash
# Build the image
docker build -t my-hwaro-site .

# Run the container
docker run -d -p 8080:80 my-hwaro-site
```

Visit `http://localhost:8080` to see your site.

## CLI Usage

You can run Hwaro commands directly using the Docker image without installing Crystal or Hwaro locally.

```bash
# Build the site
docker run --rm -v $(pwd):/site -w /site ghcr.io/hahwul/hwaro build

# Interactive shell
docker run --rm -it -v $(pwd):/site -w /site ghcr.io/hahwul/hwaro /bin/sh
```

## CI/CD Integration

### GitHub Actions

You can use the official Docker image in your GitHub Actions workflow.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container: ghcr.io/hahwul/hwaro:latest
    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: hwaro build --minify
```

For a pre-configured action, check out [Hwaro Deploy to Pages](https://github.com/marketplace/actions/hwaro-deploy-to-pages).

### GitLab CI

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
