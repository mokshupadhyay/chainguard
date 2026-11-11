#!/usr/bin/env bash
# Read-only pre-deployment checks. Sends no transactions. Never prints secrets.
# Usage: ./scripts/preflight.sh
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0; ok(){ echo "  ✓ $*"; }; bad(){ echo "  ✗ $*"; fail=1; }; warn(){ echo "  ! $*"; }

[ -f .env ] || { echo "Missing .env (cp .env.example .env and fill it)"; exit 1; }
git check-ignore -q .env && ok ".env is git-ignored" || bad ".env is NOT git-ignored"
set -a; . ./.env; set +a

echo "Config"
for v in BASE_SEPOLIA_RPC LASNA_RPC DEPLOYER_ACCOUNT DEPLOYER_ADDRESS; do [ -n "${!v:-}" ] && ok "$v set" || bad "$v missing"; done
[ -z "${DEPLOYER_PRIVATE_KEY:-}" ] && ok "no raw private key in .env" || bad "DEPLOYER_PRIVATE_KEY is set in .env — remove it and use a keystore"
[ "$fail" = 1 ] && { echo "Fix config first."; exit 1; }

echo "Networks (must be testnets)"
[ "$(cast chain-id --rpc-url "$BASE_SEPOLIA_RPC" 2>/dev/null)" = 84532 ] && ok "BASE_SEPOLIA_RPC is chain 84532" || bad "BASE_SEPOLIA_RPC is not Base Sepolia (84532)"
[ "$(cast chain-id --rpc-url "$LASNA_RPC" 2>/dev/null)" = 5318007 ] && ok "LASNA_RPC is chain 5318007" || bad "LASNA_RPC is not Lasna (5318007)"
HB=$(cast block-number --rpc-url "$BASE_SEPOLIA_RPC" 2>/dev/null || echo 0)
cast logs --from-block $((HB-1000)) --to-block "$HB" --address 0x476F44b11F5C942c58f4c8E3d0300E5710743585 --rpc-url "$BASE_SEPOLIA_RPC" >/dev/null 2>&1 \
  && ok "Base RPC allows >=1000-block getLogs" || bad "Base RPC rejects wide getLogs (indexer/dashboard would break; use publicnode)"
[ "$(cast code 0x476F44b11F5C942c58f4c8E3d0300E5710743585 --rpc-url "$BASE_SEPOLIA_RPC" 2>/dev/null | wc -c)" -gt 10 ] && ok "callback proxy has code on Base Sepolia" || bad "callback proxy missing"
[ "$(cast code 0x8888888888888888888888888888888888888888 --rpc-url "$LASNA_RPC" 2>/dev/null | wc -c)" -gt 10 ] && ok "system contract has code on Lasna" || bad "system contract missing"

echo "Deployer"
KS="${HOME}/.foundry/keystores/${DEPLOYER_ACCOUNT}"
lc() { printf '%s' "$1" | tr 'A-F' 'a-f'; }
if [ -f "$KS" ]; then
  # Foundry keystores usually have no plaintext "address" field, so ask cast.
  # cast prompts for the password on the terminal (not captured, never echoed or stored).
  PW=()
  [ -n "${KEYSTORE_PASSWORD_FILE:-}" ] && [ -f "${KEYSTORE_PASSWORD_FILE}" ] && PW=(--password-file "$KEYSTORE_PASSWORD_FILE")
  [ ${#PW[@]} -eq 0 ] && echo "  (cast will ask for the keystore password; it is not stored)"
  KA=$(cast wallet address --account "$DEPLOYER_ACCOUNT" ${PW[@]+"${PW[@]}"} | tail -n1 | tr -d '[:space:]') || KA=""
  if ! printf '%s' "$KA" | grep -Eq '^0x[0-9a-fA-F]{40}$'; then
    bad "could not derive keystore address (wrong password or unreadable keystore)"
  elif [ "$(lc "$KA")" = "$(lc "${DEPLOYER_ADDRESS}")" ]; then
    ok "keystore '$DEPLOYER_ACCOUNT' matches DEPLOYER_ADDRESS ($KA)"
  else
    bad "keystore address $KA != DEPLOYER_ADDRESS"
  fi
else bad "keystore '$DEPLOYER_ACCOUNT' not found (cast wallet import $DEPLOYER_ACCOUNT --interactive)"; fi
BE=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$BASE_SEPOLIA_RPC" --ether 2>/dev/null || echo 0)
LR=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$LASNA_RPC" --ether 2>/dev/null || echo 0)
echo "  Base Sepolia ETH: $BE   Lasna lREACT: $LR"
awk "BEGIN{exit !($BE >= 0.01)}" && ok "Base ETH sufficient for deploys + guards (>=0.01)" || bad "need >=0.01 Base Sepolia ETH"
awk "BEGIN{exit !($LR >= 2.5)}" && ok "lREACT sufficient (>=2.5)" || warn "lREACT < 2.5: request from faucet (needs ~0.03 ETH extra on Base, 0.05 ETH = 5 lREACT)"

echo "Build & tests"
[ -d contracts/lib/reactive-lib-omni/src ] && ok "reactive-lib-omni present" || bad "run ./scripts/install-deps.sh"
FORGE=$(./scripts/find-forge.sh 2>/dev/null) || { bad "Foundry forge not found (another 'forge' on PATH?) — see docs/DEPLOYMENT.md §G"; FORGE=""; }
[ -n "$FORGE" ] && { (cd contracts && "$FORGE" test -q >/dev/null 2>&1) && ok "forge test passes" || bad "forge test FAILS"; }
[ "$fail" = 0 ] && echo "PREFLIGHT OK" || { echo "PREFLIGHT FAILED"; exit 1; }
