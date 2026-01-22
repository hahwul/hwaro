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
LABEL org.opencontainers.image.title="Hwaro"
LABEL org.opencontainers.image.version="0.1.0"
LABEL org.opencontainers.image.description="Hwaro (화로) is a lightweight and fast static site generator written in Crystal."
LABEL org.opencontainers.image.authors="HAHWUL <hahwul@gmail.com>"
LABEL org.opencontainers.image.source=https://github.com/hahwul/hwaro
LABEL org.opencontainers.image.documentation="https://github.com/hahwul/hwaro"
LABEL org.opencontainers.image.licenses=MIT

RUN apt-get update && \
    apt-get install -y --no-install-recommends libxml2 zlib1g libyaml-0-2 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=builder /hwaro/bin/hwaro /usr/local/bin/hwaro

CMD ["hwaro"]
