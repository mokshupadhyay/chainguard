#!/usr/bin/env bash
# Read-only post-deployment checks. Usage: ./scripts/verify-deployment.sh  (needs MOCK_ERC20, CHAINGUARD_REACTIVE, GUARD_FACTORY in .env)
set -uo pipefail
cd "$(dirname "$0")/.."; set -a; . ./.env; set +a
fail=0; ok(){ echo "  ✓ $*"; }; bad(){ echo "  ✗ $*"; fail=1; }
PROXY=0x476F44b11F5C942c58f4c8E3d0300E5710743585
lc(){ echo "$1" | tr 'A-F' 'a-f'; }
code(){ [ "$(cast code "$1" --rpc-url "$2" 2>/dev/null | wc -c)" -gt 10 ]; }
code "$MOCK_ERC20" "$BASE_SEPOLIA_RPC" && ok "token has code (Base)" || bad "token missing"
code "$GUARD_FACTORY" "$BASE_SEPOLIA_RPC" && ok "factory has code (Base)" || bad "factory missing"
code "$CHAINGUARD_REACTIVE" "$LASNA_RPC" && ok "reactive has code (Lasna)" || bad "reactive missing"
[ "$(lc "$(cast call "$GUARD_FACTORY" 'reactive()(address)' --rpc-url "$BASE_SEPOLIA_RPC")")" = "$(lc "$CHAINGUARD_REACTIVE")" ] && ok "factory.reactive == reactive" || bad "factory.reactive mismatch"
[ "$(lc "$(cast call "$GUARD_FACTORY" 'callbackProxy()(address)' --rpc-url "$BASE_SEPOLIA_RPC")")" = "$(lc $PROXY)" ] && ok "factory.callbackProxy == official proxy" || bad "proxy mismatch"
[ "$(cast call "$CHAINGUARD_REACTIVE" 'ORIGIN_CHAIN_ID()(uint256)' --rpc-url "$LASNA_RPC")" = 84532 ] && ok "reactive origin chain = 84532" || bad "origin chain mismatch"
[ "$(lc "$(cast call "$CHAINGUARD_REACTIVE" 'admin()(address)' --rpc-url "$LASNA_RPC")")" = "$(lc "$DEPLOYER_ADDRESS")" ] && ok "reactive admin == deployer" || bad "admin mismatch"
[ "$(lc "$(cast call "$CHAINGUARD_REACTIVE" 'factory()(address)' --rpc-url "$LASNA_RPC")")" = "$(lc "$GUARD_FACTORY")" ] && ok "reactive.factory == GUARD_FACTORY (setFactory done)" || bad "reactive.factory not set to GUARD_FACTORY — run setFactory BEFORE creating any Guard"
[ "$(cast call "$CHAINGUARD_REACTIVE" 'isWatchedToken(address)(bool)' "$MOCK_ERC20" --rpc-url "$LASNA_RPC")" = true ] && ok "token is on the reactive allowlist" || bad "token not allowlisted"
echo "  maxGuards=$(cast call "$CHAINGUARD_REACTIVE" 'maxGuards()(uint256)' --rpc-url "$LASNA_RPC")  guardCount=$(cast call "$CHAINGUARD_REACTIVE" 'guardCount()(uint256)' --rpc-url "$LASNA_RPC")"
RB=$(cast balance "$CHAINGUARD_REACTIVE" --rpc-url "$LASNA_RPC" --ether); echo "  reactive lREACT balance: $RB"
awk "BEGIN{exit !($RB >= 1)}" && ok "reactive funded (>=1 lREACT)" || bad "fund the reactive contract"
echo "  active filters mentioning reactive (best effort):"
cast rpc rnk_getFilters --rpc-url "$LASNA_RPC" 2>/dev/null | jq -r --arg a "$(lc "$CHAINGUARD_REACTIVE")" '.. | objects | select((.Contract? // "") | ascii_downcase == $a) | "    active=\(.Active) rvm=\(.RvmId)"' 2>/dev/null | sort | uniq -c | head
[ "$fail" = 0 ] && echo "VERIFY OK" || { echo "VERIFY FAILED"; exit 1; }
