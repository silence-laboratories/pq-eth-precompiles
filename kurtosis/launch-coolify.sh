#!/usr/bin/env bash
set -euo pipefail

ERIGON_IMAGE="${ERIGON_IMAGE:-ghcr.io/silence-laboratories/erigon-ntt:latest}"
ARGS_FILE="/app/devnet/network_params.yaml"

echo "── Pulling Erigon image: $ERIGON_IMAGE"
docker pull "$ERIGON_IMAGE"
docker tag "$ERIGON_IMAGE" erigon-ntt:latest

echo "── Launching Kurtosis devnet (falcon-devnet)..."
kurtosis enclave rm -f falcon-devnet 2>/dev/null || true
kurtosis run --enclave falcon-devnet github.com/ethpandaops/ethereum-package \
    --args-file "$ARGS_FILE"

RPC=$(kurtosis port print falcon-devnet el-1-erigon-lighthouse rpc 2>/dev/null || echo "pending")
echo ""
echo "══════════════════════════════════════════"
echo "  Falcon-512 PQ Devnet running!"
echo "  EL RPC: http://$RPC"
echo "══════════════════════════════════════════"

tail -f /dev/null
