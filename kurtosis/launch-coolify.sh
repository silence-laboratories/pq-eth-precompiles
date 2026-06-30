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
        --args-file "$ARGS_FILE" || echo "WARNING: kurtosis run failed"

    RPC_URL=$(kurtosis port print falcon-devnet el-1-erigon-lighthouse rpc 2>/dev/null || true)
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
    else
        echo "WARNING: could not determine Kurtosis RPC port — devnet not proxied"
    fi
else
    echo "ERROR: erigon-ntt image unavailable. Devnet NOT started."
    echo "Fix: make GHCR package public or provide GHCR_TOKEN with read:packages scope."
fi

echo "── Container alive for debugging. Check logs above for errors."
tail -f /dev/null
