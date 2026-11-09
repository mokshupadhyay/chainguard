#!/usr/bin/env bash
# SENDS REAL TESTNET TRANSACTIONS (Base Sepolia). Run only after approving. Prints every tx hash.
# Usage: ./scripts/live-loop.sh [SPENDER]   (default spender: 0x…dEaD)
set -euo pipefail
cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
SPENDER=${1:-0x000000000000000000000000000000000000dEaD}
MAX=115792089237316195423570985008687907853269984665640564039457584007913129639935
SIGN=(--account "$DEPLOYER_ACCOUNT" --rpc-url "$BASE_SEPOLIA_RPC"); [ -n "${KEYSTORE_PASSWORD_FILE:-}" ] && SIGN+=(--password-file "$KEYSTORE_PASSWORD_FILE")
tx(){ cast send "$@" "${SIGN[@]}" --json | jq -r '"    tx=\(.transactionHash) status=\(.status) block=\(.blockNumber)"'; }
lc(){ echo "$1" | tr 'A-F' 'a-f'; }

echo "1) createGuard (+0.002 ETH callback gas)"; tx "$GUARD_FACTORY" 'createGuard()' --value 0.002ether
GUARD=$(cast call "$GUARD_FACTORY" 'guardsOf(address)(address[])' "$DEPLOYER_ADDRESS" --rpc-url "$BASE_SEPOLIA_RPC" | tr -d '[]' | tr ',' '\n' | tail -1 | tr -d ' ')
echo "   guard=$GUARD"
echo "2) mint 1000 demo tokens into the Guard"; tx "$MOCK_ERC20" 'mint(address,uint256)' "$GUARD" 1000ether
echo "3) wait for the Guard to be REGISTERED on Lasna (react() handled the factory's GuardCreated and subscribed to it)"
for i in $(seq 1 60); do
  R=$(cast call "$CHAINGUARD_REACTIVE" 'registered(address)(bool)' "$GUARD" --rpc-url "$LASNA_RPC" || true)
  [ "$R" = true ] && { echo "   registered after ~$((i*3))s"; break; }; sleep 3
  [ "$i" = 60 ] && { echo "   ✗ Guard never registered (is setFactory done? reactive funded? maxGuards reached? Guard created before setFactory?)"; exit 1; }
done
echo "   waiting for Lasna's confirmation callback to reach the Guard (guard.ready() on Base Sepolia) — approvals are blocked on-chain until then"
for i in $(seq 1 60); do
  RD=$(cast call "$GUARD" 'ready()(bool)' --rpc-url "$BASE_SEPOLIA_RPC" || true)
  [ "$RD" = true ] && { echo "   ready after ~$((i*3))s"; break; }; sleep 3
  [ "$i" = 60 ] && { echo "   ✗ Guard never confirmed (reactive funded? callback proxy debt? check Reactscan for the registration react tx)"; exit 1; }
done
echo "   mirrored policy: $(cast call "$CHAINGUARD_REACTIVE" 'policies(address)(bool,bool,uint256)' "$GUARD" --rpc-url "$LASNA_RPC" | tr '\n' ' ')"
echo "4) UNLIMITED approval by the Guard to $SPENDER"; tx "$GUARD" 'approveToken(address,address,uint256)' "$MOCK_ERC20" "$SPENDER" "$MAX"
echo "   allowance now: $(cast call "$MOCK_ERC20" 'allowance(address,address)(uint256)' "$GUARD" "$SPENDER" --rpc-url "$BASE_SEPOLIA_RPC")"
echo "5) waiting for reactive revoke (up to 3 min)"
for i in $(seq 1 60); do
  A=$(cast call "$MOCK_ERC20" 'allowance(address,address)(uint256)' "$GUARD" "$SPENDER" --rpc-url "$BASE_SEPOLIA_RPC" | awk '{print $1}')
  [ "$A" = 0 ] && { echo "   ✓ allowance == 0 after ~$((i*3))s"; break; }; sleep 3
  [ "$i" = 60 ] && { echo "   ✗ not revoked in 3 min — see docs/DEPLOYMENT.md troubleshooting"; exit 1; }
done
echo "6) find the revoke (callback) tx"
HB=$(cast block-number --rpc-url "$BASE_SEPOLIA_RPC")
cast logs --from-block $((HB-1500)) --to-block "$HB" --address "$GUARD" 'Revoked(address indexed,address indexed,uint256)' --rpc-url "$BASE_SEPOLIA_RPC" --json | jq -r '.[] | "    revoke tx=\(.transactionHash) block=\(.blockNumber)"'
echo "Reactive-side tx: find 'RevokeRequested' for $GUARD at https://lasna.reactscan.net/address/$CHAINGUARD_REACTIVE"
echo "GUARD=$GUARD (record in README)"
