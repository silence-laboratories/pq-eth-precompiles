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

        # Traefik Docker provider falls back to 127.0.0.1 for host-mode containers,
        # which is Traefik's own loopback — unreachable. Instead, use Traefik's file
        # provider (/data/coolify/proxy/dynamic/ is watched by Traefik with --providers.file).
        # Traefik has extra_hosts: host.docker.internal:host-gateway, so it CAN reach
        # the host's port 8545 (where socat is listening on 0.0.0.0).
        echo "── Writing Traefik file provider config (priority 200 overrides Docker provider)..."
        docker rm -f pq-rpc-proxy 2>/dev/null || true
        docker run --rm -i \
            -v /data/coolify/proxy:/traefik-proxy \
            alpine sh << 'DOCKEREOF' || echo "WARNING: Failed to write Traefik file config"
mkdir -p /traefik-proxy/dynamic
cat > /traefik-proxy/dynamic/pq-devnet.yaml << 'YAMLEOF'
http:
  middlewares:
    pq-gzip:
      compress: {}
    pq-redirect-to-https:
      redirectScheme:
        scheme: https
        permanent: true
  routers:
    pq-devnet-https:
      rule: "Host(`pq-precompiles-devnet.demo.silencelaboratories.com`)"
      entryPoints: [https]
      service: pq-devnet
      tls:
        certResolver: letsencrypt
      middlewares: [pq-gzip]
      priority: 200
    pq-devnet-http:
      rule: "Host(`pq-precompiles-devnet.demo.silencelaboratories.com`)"
      entryPoints: [http]
      service: pq-devnet
      middlewares: [pq-redirect-to-https]
      priority: 200
  services:
    pq-devnet:
      loadBalancer:
        servers:
          - url: http://host.docker.internal:8545
YAMLEOF
echo "Traefik file config written."
DOCKEREOF
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

if docker image inspect erigon-ntt:latest >/dev/null 2>&1; then
    (
        while true; do
            sleep 60
            echo "── [periodic] eth_blockNumber:"
            curl -s -X POST "http://127.0.0.1:${EXPOSED_RPC_PORT}" \
                -H "Content-Type: application/json" \
                -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' || true
            echo
            echo "── [periodic] cl-1-lighthouse-erigon logs (tail 40):"
            kurtosis service logs falcon-devnet cl-1-lighthouse-erigon --tail 40 2>&1 || true
            echo "── [periodic] vc-1-erigon-lighthouse logs (tail 20):"
            kurtosis service logs falcon-devnet vc-1-erigon-lighthouse --tail 20 2>&1 || true
        done
    ) &
fi

tail -f /dev/null
