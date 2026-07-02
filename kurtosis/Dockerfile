FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl bash ca-certificates gnupg lsb-release socat \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI only (uses host socket via volume mount)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# Kurtosis CLI via official apt repo. Cache-busted per deploy (via Coolify's
# auto-injected COOLIFY_CONTAINER_NAME arg) so we always get the latest CLI,
# since newer ethereum-package Starlark modules (e.g. zkboost's GpuConfig)
# require SDK types that older Kurtosis CLI releases don't have.
ARG COOLIFY_CONTAINER_NAME
RUN echo "cache-bust: ${COOLIFY_CONTAINER_NAME}" && \
    echo "deb [trusted=yes] https://apt.fury.io/kurtosis-tech/ /" > /etc/apt/sources.list.d/kurtosis.list && \
    apt-get update && apt-get install -y kurtosis-cli && \
    rm -rf /var/lib/apt/lists/* && \
    kurtosis version

COPY devnet /app/devnet
COPY scripts /app/scripts
COPY launch-coolify.sh /app/launch-coolify.sh
RUN chmod +x /app/launch-coolify.sh

WORKDIR /app

EXPOSE 8545 8546

CMD ["/app/launch-coolify.sh"]
