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

# Kurtosis CLI
RUN KURTOSIS_VERSION=$(curl -s https://api.github.com/repos/kurtosis-tech/kurtosis/releases/latest \
    | grep -m1 '"tag_name"' | cut -d'"' -f4) && \
    curl -sSL "https://github.com/kurtosis-tech/kurtosis/releases/download/${KURTOSIS_VERSION}/kurtosis_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin && \
    kurtosis version

COPY devnet /app/devnet
COPY scripts /app/scripts
COPY launch-coolify.sh /app/launch-coolify.sh
RUN chmod +x /app/launch-coolify.sh

WORKDIR /app

EXPOSE 8545 8546

CMD ["/app/launch-coolify.sh"]
