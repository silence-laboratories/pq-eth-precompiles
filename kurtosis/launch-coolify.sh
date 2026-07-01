#!/usr/bin/env bash
set -x

ERIGON_IMAGE="${ERIGON_IMAGE:-ghcr.io/silence-laboratories/erigon-ntt:latest}"
ARGS_FILE="/app/devnet/network_params.yaml"
EXPOSED_RPC_PORT="${RPC_PORT:-8545}"

echo "── Docker socket check:"
docker version || echo "WARNING: docker CLI cannot reach daemon (socket not mounted?)"

if [ -n "${GHCR_TOKEN:-}" ]; then
    echo "── Logging in to ghcr.io..."
    echo "$GHCR_TOKEN" | docker login ghcr.io -u "${GHCR_USER:-Rhonstin}" --password-stdin \
        || echo "WARNING: docker login failed (token may lack read:packages scope)"
fi

echo "── Pulling Erigon image: $ERIGON_IMAGE"
if docker pull "$ERIGON_IMAGE"; then
    docker tag "$ERIGON_IMAGE" erigon-ntt:latest
else
    echo "WARNING: docker pull failed — checking for cached image..."
    docker image inspect erigon-ntt:latest 2>/dev/null \
        || echo "ERROR: image not found locally either"
fi

if docker image inspect erigon-ntt:latest >/dev/null 2>&1; then
    echo "── Launching Kurtosis devnet (falcon-devnet)..."
    kurtosis enclave rm -f falcon-devnet 2>/dev/null || true
    kurtosis run --enclave falcon-devnet github.com/ethpandaops/ethereum-package@5.0.1 \
        --args-file "$ARGS_FILE" || echo "WARNING: kurtosis run exited non-zero"

    # Port name in ethereum-package 5.0.1 erigon launcher is "ws-rpc" (not "rpc")
    RPC_URL=$(kurtosis port print falcon-devnet el-1-erigon-lighthouse ws-rpc 2>/dev/null || true)
    KURTOSIS_PORT=$(echo "$RPC_URL" | grep -oE '[0-9]+$' || true)

    echo ""
    echo "══════════════════════════════════════════"
    echo "  Falcon-512 PQ Devnet running!"
    echo "  Kurtosis RPC:  http://$RPC_URL"
    echo "  Exposed port:  $EXPOSED_RPC_PORT"
    echo "══════════════════════════════════════════"

    if [ -n "$KURTOSIS_PORT" ]; then
        echo "── Proxying 0.0.0.0:$EXPOSED_RPC_PORT → 127.0.0.1:$KURTOSIS_PORT"
        socat TCP-LISTEN:"$EXPOSED_RPC_PORT",fork,reuseaddr TCP:127.0.0.1:"$KURTOSIS_PORT" &

        # Traefik with providers.docker.network=coolify only routes to containers
        # that have an IP in the coolify network. host-mode containers have no such
        # IP, so Traefik returns "no available server". Fix: spawn a sidecar in the
        # coolify network that proxies to this container's socat (0.0.0.0:8545).
        echo "── Starting rpc-proxy in coolify Docker network for Traefik routing..."
        docker rm -f pq-rpc-proxy 2>/dev/null || true
        docker run -d \
            --name pq-rpc-proxy \
            --restart unless-stopped \
            --network coolify \
            --add-host "host.docker.internal:host-gateway" \
            --label "traefik.enable=true" \
            --label "traefik.http.services.http-0-ynd5qiiwxt4l1xcshlli1qxr.loadbalancer.server.port=8545" \
            --label "traefik.http.services.https-0-ynd5qiiwxt4l1xcshlli1qxr.loadbalancer.server.port=8545" \
            alpine/socat \
            TCP-LISTEN:8545,fork,reuseaddr "TCP:host.docker.internal:$EXPOSED_RPC_PORT" \
            || echo "WARNING: rpc-proxy failed to start (coolify network may not exist or alpine/socat unavailable)"
    else
        echo "WARNING: could not determine Kurtosis ws-rpc port — devnet not proxied"
        echo "── Enclave services:"
        kurtosis enclave inspect falcon-devnet 2>/dev/null || true
    fi
else
    echo "ERROR: erigon-ntt image unavailable. Devnet NOT started."
    echo "Fix: provide GHCR_TOKEN with read:packages scope."
fi

echo "── Container alive for debugging. Check logs above for errors."
tail -f /dev/null
