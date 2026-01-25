##= BUILDER =##
FROM 84codes/crystal:latest-debian-13 AS builder
WORKDIR /hwaro
COPY . .

RUN apt-get update && \
    apt-get install -y --no-install-recommends zlib1g-dev pkg-config && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    shards install --production && \
    shards build --release --no-debug --production

##= RUNNER =##
FROM debian:13-slim

# Standard OCI labels
LABEL org.opencontainers.image.title="Hwaro"
LABEL org.opencontainers.image.description="Hwaro (화로) is a lightweight and fast static site generator written in Crystal."
LABEL org.opencontainers.image.authors="HAHWUL <hahwul@gmail.com>"
LABEL org.opencontainers.image.source=https://github.com/hahwul/hwaro
LABEL org.opencontainers.image.documentation="https://github.com/hahwul/hwaro"
LABEL org.opencontainers.image.licenses=MIT

# GitHub Action labels
LABEL "com.github.actions.name"="Hwaro Deploy to Pages"
LABEL "com.github.actions.description"="Build and deploy a Hwaro site to GitHub Pages"
LABEL "com.github.actions.icon"="octagon"
LABEL "com.github.actions.color"="white"

# Set default locale for the environment
ENV LC_ALL=C.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8

RUN apt-get update && \
    apt-get install -y --no-install-recommends libxml2 zlib1g libyaml-0-2 git ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=builder /hwaro/bin/hwaro /usr/local/bin/hwaro
COPY docker/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
