#!/usr/bin/env bash
# Auto-deploys the ML-DSA demo contracts (MLDSAWallet, DemoRecipient,
# SimpleERC20/PQT) once the Kurtosis enclave is producing blocks, and funds the
# demo relayer with gas.
#
# Why: the enclave is recreated from scratch (fresh genesis) on every redeploy,
# wiping all contracts and balances. The demo frontends (pq-demo-react,
# bitgo-wallet-demo, examples-hub) and the explorer's tracked-wallets.json
# hardcode the contract addresses, which stay stable ONLY because the deployer
# starts at nonce 0 on a fresh chain and the three CREATE transactions always
# run in the same order: MLDSAWallet (nonce 0), DemoRecipient (1), SimpleERC20 (2).
#
# Bytecode in /app/demo-contracts/*.bin is compiled from
# silence-laboratories/pq-eth-precompiles-demo `sol/` with:
#   solc 0.8.25 --optimize --combined-json abi,bin
# Regenerate the .bin files whenever those contracts change.
set -x

RPC="${RPC_URL:-http://127.0.0.1:${RPC_PORT:-8545}}"
BIN_DIR="${BIN_DIR:-/app/demo-contracts}"

# Well-known public Anvil/Hardhat test account #0 — prefunded in the devnet
# genesis (see devnet/network_params.yaml). Test-only key, never real funds.
DEPLOYER_KEY="${DEPLOYER_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

# Relayer used by the demo frontends (VITE_PQ_RELAYER_PRIVATE_KEY there, also a
# committed test key). It pays gas for relayed txs and is wiped every genesis.
RELAYER_ADDRESS="${RELAYER_ADDRESS:-0xe158bE6E65EbB02CF4b8d12B8fA2ce94226Df382}"
RELAYER_FUND_ETHER="${RELAYER_FUND_ETHER:-1000}"

# CREATE address of MLDSAWallet at deployer nonce 0 — the idempotency marker.
EXPECTED_WALLET="0x5fbdb2315678afecb367f032d93f642f64180aa3"

TOKEN_NAME="PQ Demo Token"
TOKEN_SYMBOL="PQT"
TOKEN_DECIMALS="18"
TOKEN_SUPPLY="1000000000000000000000"

echo "── [demo-deploy] Waiting for devnet RPC at $RPC to produce blocks..."
BLOCK=""
for _ in $(seq 1 90); do
    BLOCK=$(cast block-number --rpc-url "$RPC" 2>/dev/null || true)
    if [ -n "$BLOCK" ] && [ "$BLOCK" -ge 1 ] 2>/dev/null; then
        break
    fi
    sleep 10
done
if [ -z "$BLOCK" ] || ! [ "$BLOCK" -ge 1 ] 2>/dev/null; then
    echo "WARNING: [demo-deploy] devnet RPC never became ready — demo contracts NOT deployed"
    exit 0
fi
echo "── [demo-deploy] Chain is live (block $BLOCK)"

deploy_contract() {
    # $1 = .bin file, $2 = optional abi-encoded constructor args (without 0x)
    local bytecode="0x$(tr -d '[:space:]' < "$BIN_DIR/$1")${2:-}"
    # NB: cast treats everything after `--create <CODE>` as sig/args — all
    # flags must come before it.
    cast send --private-key "$DEPLOYER_KEY" --rpc-url "$RPC" --json --create "$bytecode" \
        | grep -oE '"contractAddress":"0x[0-9a-fA-F]{40}"' | cut -d'"' -f4
}

DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_KEY")
CODE=$(cast code "$EXPECTED_WALLET" --rpc-url "$RPC" 2>/dev/null || echo "0x")

if [ -n "$CODE" ] && [ "$CODE" != "0x" ]; then
    echo "── [demo-deploy] Demo contracts already present at canonical addresses — skipping deploy"
else
    NONCE=$(cast nonce "$DEPLOYER" --rpc-url "$RPC" 2>/dev/null || echo "")
    if [ "$NONCE" != "0" ]; then
        echo "WARNING: [demo-deploy] deployer $DEPLOYER has nonce '$NONCE' (expected 0 on a fresh"
        echo "genesis), so CREATE addresses would NOT match the ones hardcoded in the demo"
        echo "frontends and explorer. Deploy manually with pq-eth-precompiles-demo instead."
    else
        WALLET_ADDR=$(deploy_contract MLDSAWallet.bin) \
            || echo "WARNING: [demo-deploy] MLDSAWallet deploy failed"
        RECIPIENT_ADDR=$(deploy_contract DemoRecipient.bin) \
            || echo "WARNING: [demo-deploy] DemoRecipient deploy failed"
        if [ -n "${WALLET_ADDR:-}" ]; then
            CTOR=$(cast abi-encode "constructor(string,string,uint8,uint256,address)" \
                "$TOKEN_NAME" "$TOKEN_SYMBOL" "$TOKEN_DECIMALS" "$TOKEN_SUPPLY" "$WALLET_ADDR")
            TOKEN_ADDR=$(deploy_contract SimpleERC20.bin "${CTOR#0x}") \
                || echo "WARNING: [demo-deploy] SimpleERC20 deploy failed"
        fi
        echo "── [demo-deploy] MLDSAWallet:   ${WALLET_ADDR:-FAILED}"
        echo "── [demo-deploy] DemoRecipient: ${RECIPIENT_ADDR:-FAILED}"
        echo "── [demo-deploy] SimpleERC20:   ${TOKEN_ADDR:-FAILED}"
        if [ "${WALLET_ADDR,,}" != "$EXPECTED_WALLET" ]; then
            echo "WARNING: [demo-deploy] MLDSAWallet landed at an unexpected address —"
            echo "update the demo frontends and explorer/public/tracked-wallets.json!"
        fi
    fi
fi

# Fund the relayer whenever it is below half the target (fresh genesis = 0).
BAL=$(cast balance "$RELAYER_ADDRESS" --ether --rpc-url "$RPC" 2>/dev/null || echo "0")
BAL_INT="${BAL%%.*}"
[ -n "$BAL_INT" ] || BAL_INT=0
if [ "$BAL_INT" -lt "$((RELAYER_FUND_ETHER / 2))" ] 2>/dev/null; then
    echo "── [demo-deploy] Funding relayer $RELAYER_ADDRESS with ${RELAYER_FUND_ETHER} ETH (balance: $BAL)"
    cast send "$RELAYER_ADDRESS" --value "${RELAYER_FUND_ETHER}ether" \
        --private-key "$DEPLOYER_KEY" --rpc-url "$RPC" --json >/dev/null \
        || echo "WARNING: [demo-deploy] relayer funding failed"
else
    echo "── [demo-deploy] Relayer balance OK ($BAL ETH) — no funding needed"
fi

# Final sanity: PQT balance held by the wallet (what the demos display).
cast call "${TOKEN_ADDR:-0x9fe46736679d2d9a65f0992f2272de9f3c7fa6e0}" \
    "balanceOf(address)(uint256)" "$EXPECTED_WALLET" --rpc-url "$RPC" \
    || echo "WARNING: [demo-deploy] balanceOf sanity check failed"

echo "── [demo-deploy] Done."
