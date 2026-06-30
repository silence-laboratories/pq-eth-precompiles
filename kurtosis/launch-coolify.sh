#!/usr/bin/env bash
set -euo pipefail

ERIGON_IMAGE="${ERIGON_IMAGE:-ghcr.io/silence-laboratories/erigon-ntt:latest}"
ARGS_FILE="/app/devnet/network_params.yaml"
EXPOSED_RPC_PORT="${RPC_PORT:-8545}"

if [ -n "${GHCR_TOKEN:-}" ]; then
    echo "── Logging in to ghcr.io..."
    echo "$GHCR_TOKEN" | docker login ghcr.io -u Rhonstin --password-stdin
fi

echo "── Pulling Erigon image: $ERIGON_IMAGE"
docker pull "$ERIGON_IMAGE"
docker tag "$ERIGON_IMAGE" erigon-ntt:latest

echo "── Launching Kurtosis devnet (falcon-devnet)..."
kurtosis enclave rm -f falcon-devnet 2>/dev/null || true
kurtosis run --enclave falcon-devnet github.com/ethpandaops/ethereum-package \
    --args-file "$ARGS_FILE"

# Kurtosis assigns random ports on the host; proxy to stable $EXPOSED_RPC_PORT
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
    echo "WARNING: could not determine Kurtosis RPC port"
fi

tail -f /dev/null
