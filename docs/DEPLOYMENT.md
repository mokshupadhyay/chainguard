# Deployment

> **Status: nothing deployed, no transactions sent.** Findings below were verified on 2026-11-09 by reading
> https://dev.reactive.network/ (callback-contracts, reactive-contracts, economy, reactive-mainnet, origins-and-destinations),
> the pinned `reactive-lib-omni` v0.1.0 source, read-only RPC calls, and Foundry fork *simulations* (no broadcast).
> Re-verify fees and free tiers before relying on them.

## A. Verified against the Reactive Omni APIs
| Item | Our code | Verified |
|---|---|---|
| `react` | `react(LogRecord calldata) external override onlySystem` | matches `IReactive`; `onlySystem` = `msg.sender == 0x8888…8888`; compiles against pinned lib; `react()` inherits no extra auth beyond `onlySystem` |
| Runtime subscribe | `SYSTEM.subscribe(chainId, contract, topic0, topic1, IGNORE, IGNORE)` called from inside `react()` | docs (reactive-contracts, read 2026-11-09): subscriptions "aren't limited to the constructor" and may be changed "from inside react()"; at least one criterion must be specific; the contract pays gas; identical subscriptions behave as one (but both calls are billed). **Not documented:** how soon a new subscription takes effect → the Guard blocks approvals/policy changes until Lasna's on-chain confirmation callback arrives (see §C2) |
| Callback request | `SYSTEM.requestCallbackV_1_0({chainId, recipient, gasLimit: uint64, payload})` | struct fields match `ISystemContract`; gas limit 400,000 (docs: <100,000 is ignored) |
| Payload | approval-triggered: `revokeIfUnchanged(address,address,address,uint256)` with `(address(0), token, spender, value)` — the Guard skips it (event `RevokeSkipped`) if the allowance is no longer `value`; spender-removal: `revoke(address,address,address)` | first arg `address(0)` placeholder, overwritten by the network with the reactive contract address |
| Callback auth | `GuardModule is AbstractCallback`; `revoke(...)` has `onlyServiceProvider` + `onlyCallbackSender(first arg)` | the pattern the docs prescribe; we never mix `AbstractCallback` with `AbstractReactive` (docs: won't compile) |
| Proxy | `0x476F44b11F5C942c58f4c8E3d0300E5710743585` (Base Sepolia) | docs; bytecode present on chain; checked again by `verify-deployment.sh` |
| Recipient | the user's Guard (`recipient: guard`) | Guard holds ETH for callback fees (factory forwards `msg.value`; `receive()` and proxy `depositTo` also work) |
| Lasna | chain 5318007, system `0x8888…8888`, token **lREACT**, RPC `lasna-rpc.rnk.dev`, explorer `lasna.reactscan.net` | docs + live `cast chain-id` + bytecode |
| Library version | v0.1.0 = commit `3ade0dc…` = `master` HEAD | `git ls-remote` |

**Only provable live (not by any local test):** that runtime subscriptions from `react()` actually start delivering events, that the proxy actually delivers `revoke` with our reactive address injected, and that Lasna accepts our bytecode (`evm_version = cancun`). A failed deployment costs ≲ 0.2 lREACT.

## B. Constructor dependencies and deployment order
| Contract | Chain | Constructor args | Needs first |
|---|---|---|---|
| `MockERC20` | Base Sepolia | `(name, symbol)` | — |
| `ChainGuardReactive` | Lasna | `(originChainId = 84532, tokens[] = [MockERC20] (≤ 8, fixed), maxGuards = 50)` — **no subscriptions in the constructor** | `MockERC20` address |
| `GuardFactory` | Base Sepolia | `(callbackProxy = 0x476F…3585 (fixed in script), reactive)` | `ChainGuardReactive` address |
| `reactive.setFactory(factory)` | Lasna (admin tx, once) | `(factory)` — subscribes to that factory's `GuardCreated` | factory address; **must precede the first `createGuard`** |
| `GuardModule` | Base Sepolia | created by the factory: `(owner = msg.sender, proxy, reactive, Policy(true,true,0))`, ETH forwarded | factory |

The docs mandate no order; the real constraint is that `AbstractCallback` stores the reactive address as an **immutable** (no setter; a wrong value means redeploy), and that the reactive contract must hold lREACT **before** its first event ("a contract in debt receives nothing"). The order Token → Reactive → fund → Factory → `setFactory` → Guard satisfies both, plus the new rule that a Guard created before `setFactory` is never registered (redeploy that Guard).

## C. Subscription design — spam issue resolved
**Finding (previous design):** the constructor subscribed to `ChainGuardPolicySet` from **any** emitter on Base Sepolia (`contract = address(0)`). Reactive delivers every matching log and bills the contract's gas, so any contract could emit that event and make `react()` run at our lREACT expense (~0.01 lREACT each; the old test `test_spoofedPolicyEventOnlyAffectsEmitter` in commit `694c5b8` shows `react()` accepting such a log). It protected policy *integrity* but not our balance. Same exposure existed for registered-token `Approval`s from any owner.

**Fix implemented (this change):**
- Constructor makes no subscriptions. `setFactory` (admin, once) subscribes only to the trusted `GuardFactory`'s `GuardCreated`.
- `GuardCreated` now carries the initial policy (the Guard's constructor event fires before Lasna can subscribe).
- On a valid `GuardCreated`, `react()` registers the Guard and, at runtime, subscribes to that Guard's policy event (`contract = guard`) and to `Approval` on each allowlisted token with `topic1 = guard`.
- `react()` re-checks everything: factory-emitted `GuardCreated` only; policy events only from registered Guards; approvals only for registered Guards on allowlisted tokens.
- Bounds: ≤ 8 allowlisted tokens (fixed at construction) and `maxGuards` (50 in `DeployLasna`) so an open factory cannot force unbounded subscription work. Over-cap Guards are rejected with no further subscriptions.

**Tests (45 passing; 9 of them cover the spender allowlist, see §C3):** no constructor/wildcard subscriptions; `setFactory` admin/once/zero checks; real factory `createGuard` log (captured with `vm.recordLogs`) registers the Guard and creates exactly the scoped subscriptions; registration idempotent on replay; cap enforced; **spoofed `GuardCreated` from a non-factory emitter ignored; policy events from unregistered emitters ignored; a spoof cannot alter a registered Guard's policy; approvals for unregistered owners never revoke; a fake token claiming a registered Guard as owner never revokes**; plus the original policy/revoke/auth tests, and 9 readiness tests: registration requests a `confirmRegistered` callback to the Guard (right recipient, chain, tokens, gas ≥ 100k); the Guard is not ready before confirmation; early `approveToken`/`setPolicy` revert `NotProtected` while `withdraw`/`revokeManually` still work; confirmation accepts only the proxy + trusted reactive (not the owner or an attacker) and is idempotent; unsupported tokens revert even when ready; rejected, spoofed or replayed registrations send no confirmation.

**C2. Registration readiness (on-chain handshake).** After registering a Guard and requesting its subscriptions, `react()` sends a callback `Guard.confirmRegistered(reactive, tokens[])` through the callback proxy (same auth as `revoke`: proxy only + trusted reactive sender). Until it lands: `Guard.ready() == false`, and `approveToken` / `setPolicy` revert `NotProtected()`. After: `approveToken` also reverts `UnsupportedToken(token)` for tokens not on the confirmed allowlist (such an approval could never be auto-revoked). `withdraw`, `revokeManually`, `withdrawNative` always work. Rejected (cap), spoofed, replayed or non-factory registrations send no confirmation. A Guard that never gets confirmed (reactive unfunded/in debt) stays safe-but-inert; the frontend shows the stuck step. Costs one extra callback per Guard, billed by the same formula as a revoke (not separately measured; the 5 lREACT recommendation leaves headroom).

**Residual risks (accepted for the hackathon, documented):** (1) a registered Guard's owner can trigger `react()` for their own Guard — bounded by `maxGuards`, would need per-Guard prepayment in production; (2) the `createGuard` cap can be filled by an attacker (denial of registration for later users) — acceptable on testnet; the admin can redeploy with a larger cap; (3) ~~policy changes in the first seconds are not seen~~ — now gated on-chain (§C2), with the caveat below; (4) tokens added after deployment are not watched for existing Guards; (5) the docs do not state when a new subscription takes effect; the confirmation callback is requested in the same `react()` right after the `subscribe` calls, so it is the best available readiness signal but not a proof of activation — the live run is what verifies it.

**C3. Spender allowlist.** Guard events `SpenderModeSet(bool)` / `SpenderRuleSet(address,bool)` (owner-only, after readiness) are mirrored into `react()` through two more Guard-scoped subscriptions per registration (4 runtime subscriptions per Guard now: policy, spender mode, spender rule, token `Approval`). With the mode on, `react()` requests a revoke for **any** non-zero approval to a spender not on the list (reason `spender-not-allowed`), in addition to the unlimited/over-cap rules; `Approval(…, 0)` never triggers anything (so our own revokes cannot loop). Registration `react()` now makes 2 more `subscribe` calls: re-measure its lREACT cost on the live run (budget below was computed before this change; the 5 lREACT recommendation still has headroom).

## D. Dependency licensing (`reactive-lib-omni`)
Evidence: no `LICENSE` file; GitHub reports no license; all 8 source files say `SPDX-License-Identifier: UNLICENSED`; the same is true of Reactive's legacy `reactive-lib` and demo repos. `UNLICENSED` grants no redistribution rights by default. Reactive's own docs and hackathon require developers to import this library, so *using* it is clearly intended — but there is no written grant in the repo.
Safest approach adopted (dependency itself untouched):
1. **Do not copy or commit their source.** `contracts/lib/reactive-lib-omni/` is git-ignored; `scripts/install-deps.sh` fetches the pinned commit from Reactive's own repo. (A submodule pointer would also avoid redistribution, but it does not grant a license either — it is a convenience, not a fix.)
2. Our code only *imports/inherits*; none of their code is pasted into our files. Our MIT license covers our files only (README states this).
3. **Ask Reactive in writing** (hackathon organizers / their dev channel, or a GitHub issue on the repo) to confirm use in hackathon submissions and to add a license. Suggested text: *"reactive-lib-omni has no LICENSE and files are marked UNLICENSED. May we build on it and publish our hackathon project (which imports it, without copying it) as open source? Could you add a license file?"* — send it yourself; I have not contacted anyone.

## E. Funding budget (from simulated scripts + current fee docs)
Assumptions: prices read live — Base Sepolia base fee ≈ 0.005 gwei (max 0.011), Lasna base fee = 100 gwei (max fee 200). Gas from `forge script` simulations and `forge test --gas-report`. Callback fee per docs: `pbase × 1.1 × (gas used + 80,000)` charged to the Guard (`_gasPriceCoeffPer1000 = 1100`, `_extraGas = 80000`, read on-chain).

| Cost | Gas | ≈ Amount |
|---|---|---|
| Deploy token (Base) | 620,785 | 0.000007 ETH |
| Deploy factory (Base) | 1,380,392 | 0.000015 ETH |
| `createGuard` tx (Base) | ~785,000 | ~0.00001 ETH (+ forwarded callback funds) |
| `setFactory` tx (Lasna) | ~142,000 | ~0.014 lREACT |
| Guard registration `react()` (1 token) | ≤ ~290,000 in tests | ≈ 0.03 lREACT (budget 0.06) |
| Callback funds per Guard | — | **0.002 ETH** ≈ >1,000 callbacks (each ≈ 0.000002 ETH) |
| Other Base txs (mint, approve…) | ~50–100k each | < 0.000002 ETH each |
| **Deploy reactive (Lasna)** | 1,774,698 (simulated on live Lasna state) | **0.18 lREACT** at 100 gwei (0.36 at the 200 gwei fee ceiling) |
| Fund reactive contract | — | 2 lREACT |
| Each revoke `react()` | ≤ ~215,000 (test max; mock system, real overhead unknown) | ≈ 0.02 lREACT (budget 0.05 with 2× margin) |
| Each policy-mirror / ignored `react()` | 60–100k | 0.006–0.01 lREACT |

**Lasna lREACT (deployer wallet):** 0.36 (deploy at ceiling) + 0.02 (`setFactory`) + 2.0 (reactive contract ≈ 40 demo cycles at 0.05) + tx gas ≈ **2.5 minimum; 5 is comfortable (~2× headroom)**. Faucet rate: 1 ETH → 100 lREACT (per tx cap 5 ETH, excess lost), so 5 lREACT = 0.05 ETH.
**Base Sepolia ETH:** faucet request 0.05 + two Guards 0.004 + all gas < 0.001 ≈ **0.06 ETH; hold 0.1 for margin.**
**Correction:** my earlier "0.4 ETH" estimate was not grounded in these numbers — retracted. The dominant Base cost is converting ETH to lREACT, not gas.
Unknowns to measure on the first live run: real gas of `react()` on Lasna (read it on Reactscan) and whether requesting a callback adds a separate Lasna charge (the economy page does not say).

## F. Mainnet safety
- Every deploy script has `require(block.chainid == …)`: Base scripts only on 84532, Lasna only on 5318007. **Tested by simulation:** running the Base scripts against Lasna, the Lasna script against Base Sepolia, and the factory script against Base **mainnet** RPC all revert before any transaction.
- The origin chain (84532) and callback proxy are constants in the scripts, not env-configurable.
- Nothing broadcasts without an explicit `--broadcast`. The signer is an encrypted keystore (`--account`), so no raw key lives in `.env` or on a command line; `preflight.sh` fails if `DEPLOYER_PRIVATE_KEY` appears in `.env`.
- `preflight.sh` also confirms both RPCs report the expected testnet chain IDs.

## G. Exact deployment sequence
Run from `ChainGuard/`. **If `forge` is not Foundry** (e.g. Atlassian Forge CLI from npm shadows it: `forge test` → "'test' is not a Forge command"), set `forge() { "$(./scripts/find-forge.sh)" "$@"; }` first — `preflight.sh` already does this itself. Do **not** paste your key anywhere but your own terminal's prompt.

```bash
# 0. one-time setup
./scripts/install-deps.sh                              # pinned reactive-lib-omni (not vendored)
cast wallet import chainguard-deployer --interactive   # you type the TESTNET-ONLY key + a password
cp .env.example .env                                   # then set DEPLOYER_ADDRESS (public address only)
./scripts/preflight.sh                                 # read-only; must print PREFLIGHT OK

# 1. lREACT (skip if preflight shows >= 2.5). 0.05 ETH -> ~5 lREACT, arrives on Lasna for DEPLOYER_ADDRESS
set -a; . ./.env; set +a
cast send 0x2afaFD298b23b62760711756088F75B7409f5967 "request(address)" $DEPLOYER_ADDRESS \
  --value 0.05ether --rpc-url $BASE_SEPOLIA_RPC --account $DEPLOYER_ACCOUNT
cast balance $DEPLOYER_ADDRESS --rpc-url $LASNA_RPC --ether     # wait until ~5

# 2. token (Base Sepolia)
cd contracts
forge script script/DeployBaseToken.s.sol --rpc-url $BASE_SEPOLIA_RPC \
  --account $DEPLOYER_ACCOUNT --sender $DEPLOYER_ADDRESS --broadcast
jq -r '.transactions[0].contractAddress' broadcast/DeployBaseToken.s.sol/84532/run-latest.json   # -> MOCK_ERC20 in ../.env

# 3. reactive contract (Lasna). If it errors, retry with --legacy (docs don't cover Lasna flags)
set -a; . ../.env; set +a
forge script script/DeployLasna.s.sol --rpc-url $LASNA_RPC \
  --account $DEPLOYER_ACCOUNT --sender $DEPLOYER_ADDRESS --broadcast
jq -r '.transactions[0].contractAddress' broadcast/DeployLasna.s.sol/5318007/run-latest.json     # -> CHAINGUARD_REACTIVE in ../.env

# 4. fund it IMMEDIATELY (before any event), 2 lREACT
set -a; . ../.env; set +a
cast send $CHAINGUARD_REACTIVE --value 2ether --rpc-url $LASNA_RPC --account $DEPLOYER_ACCOUNT

# 5. factory (Base Sepolia)
forge script script/DeployBaseFactory.s.sol --rpc-url $BASE_SEPOLIA_RPC \
  --account $DEPLOYER_ACCOUNT --sender $DEPLOYER_ADDRESS --broadcast
jq -r '.transactions[0].contractAddress' broadcast/DeployBaseFactory.s.sol/84532/run-latest.json # -> GUARD_FACTORY in ../.env

# 5b. trust the factory on Lasna (admin, once). MUST happen before any createGuard.
set -a; . ../.env; set +a
cast send $CHAINGUARD_REACTIVE "setFactory(address)" $GUARD_FACTORY --rpc-url $LASNA_RPC --account $DEPLOYER_ACCOUNT
cast call $CHAINGUARD_REACTIVE "factory()(address)" --rpc-url $LASNA_RPC     # must equal $GUARD_FACTORY

# 6. verify (read-only), then run the live loop (sends testnet txs; prints every hash)
cd .. && ./scripts/verify-deployment.sh
./scripts/live-loop.sh
```
`live-loop.sh` does: createGuard (+0.002 ETH) → mint → waits until the Guard is **registered** on Lasna (`registered(guard)`, i.e. react() handled `GuardCreated` and subscribed) → UNLIMITED approval → polls until allowance is 0 → prints the revoke tx. Then copy the printed hashes and the `RevokeRequested` tx from Reactscan into the README.

Success criteria: `verify-deployment.sh` prints `VERIFY OK`; live loop shows `allowance == 0`; Basescan shows `Approval` (origin), Reactscan shows the `react` tx emitting `RevokeRequested`, Basescan shows `Revoked` from the callback.

**Troubleshooting:** Guard never registered → `setFactory` not run / run after the Guard was created (create a new Guard), reactive unfunded or in debt (`cast balance`), `maxGuards` reached, or wrong `MOCK_ERC20`; approval not revoked → check Reactscan for the `react` tx, then the Guard balance (callback fee) and proxy `debt(guard)`; `Lasna script fails` → try `--legacy` or `--skip-simulation`.

## H. After deployment
Put addresses in `.env`, `frontend/.env` (`VITE_*`), and the hosting env vars; run migrations on Supabase; then follow sections 2–4 below.

### Supabase
Create a project → copy the **Session pooler** string → `cd backend && DATABASE_URL=... npm run migrate`.

### Render (backend)
Blueprint from `render.yaml` or Web Service: root `backend`, build `npm ci --include=dev && npm run build`, start `npm start`, health check `/health`. Env: `DATABASE_URL`, `CORS_ORIGIN` (Pages URL), `GUARD_FACTORY`, `MOCK_ERC20`, `CHAINGUARD_REACTIVE`, `BASE_START_BLOCK`, `LASNA_START_BLOCK` (deployment blocks). Free instances sleep — hit `/health` a minute before demos; the on-chain loop never depends on it.

### Cloudflare Pages (frontend)
Root `frontend`, build `npm run build`, output `dist` (`public/_redirects` gives SPA fallback). Public env only: `VITE_API_URL`, `VITE_MOCK_ERC20`, `VITE_GUARD_FACTORY`, `VITE_CHAINGUARD_REACTIVE`, `VITE_BASE_SEPOLIA_RPC` (`base-sepolia-rpc.publicnode.com`; `sepolia.base.org` caps getLogs at 200 blocks).

### Final checklist
- [ ] forge / backend / frontend checks green · [ ] `verify-deployment.sh` OK · [ ] hashes recorded · [ ] `/health` → `{ok:true,db:true}` · [ ] no `.env`, keystore password or `lib/reactive-lib-omni` in the repo · [ ] license question sent to Reactive
