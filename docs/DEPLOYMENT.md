# Deployment

> **Status: nothing deployed, no transactions sent.** Findings below were verified on 2026-11-09 by reading
> https://dev.reactive.network/ (callback-contracts, reactive-contracts, economy, reactive-mainnet, origins-and-destinations),
> the pinned `reactive-lib-omni` v0.1.0 source, read-only RPC calls, and Foundry fork *simulations* (no broadcast).
> Re-verify fees and free tiers before relying on them.

## A. Verified against the Reactive Omni APIs
| Item | Our code | Verified |
|---|---|---|
| `react` | `react(LogRecord calldata) external override onlySystem` | matches `IReactive`; `onlySystem` = `msg.sender == 0x8888…8888`; compiles against pinned lib; constructor run simulated on live Lasna state |
| Callback request | `SYSTEM.requestCallbackV_1_0({chainId, recipient, gasLimit: uint64, payload})` | struct fields match `ISystemContract`; gas limit 400,000 (docs: <100,000 is ignored) |
| Payload | `abi.encodeWithSignature("revoke(address,address,address)", address(0), token, spender)` | first arg `address(0)` placeholder, overwritten by the network with the reactive contract address |
| Callback auth | `GuardModule is AbstractCallback`; `revoke(...)` has `onlyServiceProvider` + `onlyCallbackSender(first arg)` | the pattern the docs prescribe; we never mix `AbstractCallback` with `AbstractReactive` (docs: won't compile) |
| Proxy | `0x476F44b11F5C942c58f4c8E3d0300E5710743585` (Base Sepolia) | docs; bytecode present on chain; checked again by `verify-deployment.sh` |
| Recipient | the user's Guard (`recipient: guard`) | Guard holds ETH for callback fees (factory forwards `msg.value`; `receive()` and proxy `depositTo` also work) |
| Lasna | chain 5318007, system `0x8888…8888`, token **lREACT**, RPC `lasna-rpc.rnk.dev`, explorer `lasna.reactscan.net` | docs + live `cast chain-id` + bytecode |
| Library version | v0.1.0 = commit `3ade0dc…` = `master` HEAD | `git ls-remote` |

**Only provable live (not by any local test):** that the proxy actually delivers `revoke` with our reactive address injected, and that Lasna accepts our bytecode (`evm_version = cancun`). A failed deployment costs ~0.1 lREACT.

## B. Constructor dependencies and deployment order
| Contract | Chain | Constructor args | Needs first |
|---|---|---|---|
| `MockERC20` | Base Sepolia | `(name, symbol)` | — |
| `ChainGuardReactive` | Lasna | `(originChainId = 84532 (fixed in script), tokens[] = [MockERC20])` — subscribes in constructor | `MockERC20` address |
| `GuardFactory` | Base Sepolia | `(callbackProxy = 0x476F…3585 (fixed in script), reactive)` | `ChainGuardReactive` address |
| `GuardModule` | Base Sepolia | created by the factory: `(owner = msg.sender, proxy, reactive, Policy(true,true,0))`, ETH forwarded | factory |

The docs mandate no order; the real constraint is that `AbstractCallback` stores the reactive address as an **immutable** (no setter; a wrong value means redeploy), and that the reactive contract must hold lREACT **before** its first event ("a contract in debt receives nothing"). The order Token → Reactive → fund → Factory → Guard satisfies both.

## C. Subscription design (intentional MVP simplification — with a known weakness)
Verified in the docs: subscriptions can be added/removed at runtime, including inside `react()`; `unsubscribe` must match all six arguments; subscribing costs gas paid by the contract; duplicates are billed.

Current design: two static subscriptions in the constructor — (1) `ChainGuardPolicySet` from **any** emitter on Base Sepolia; (2) `Approval` for each admin-registered token (`watchToken`). I chose this because it has the fewest moving parts for a first live loop. It was a simplification, but I had not verified runtime subscriptions when I made it.

**Weakness (real):** because (1) accepts any emitter, anyone can emit that event from any contract on Base Sepolia and make `react()` run, billed to our lREACT (~0.01 lREACT each at 100 gwei). Policy *integrity* is safe (policy is keyed by emitter), but lREACT can be drained. Also only registered tokens are watched.

**Recommended v2 (after the first live loop proves the callback path):** make the reactive contract subscribe to the official `GuardFactory`'s `GuardCreated` (a specific contract), then on each new Guard subscribe inside `react()` to that Guard's policy events and to `Approval(topic1 = guard)` on **any** token. That removes the griefing path and the admin token list. Cost: a one-time `setFactory(address)` on the reactive contract (factory is deployed after it), a few more tests, and redeploying (≈0.1 lREACT). Decision needed — see PROGRESS.md.

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
| `createGuard` tx (Base) | ~784,000 | ~0.00001 ETH (+ forwarded callback funds) |
| Callback funds per Guard | — | **0.002 ETH** ≈ >1,000 callbacks (each ≈ 0.000002 ETH) |
| Other Base txs (mint, approve…) | ~50–100k each | < 0.000002 ETH each |
| **Deploy reactive (Lasna)** | 1,139,309 | **0.114 lREACT** at 100 gwei (0.228 at the 200 gwei fee ceiling) |
| Fund reactive contract | — | 2 lREACT |
| Each revoke `react()` | ≤ ~215,000 (test max; real system overhead unknown) | ≈ 0.02 lREACT (budget 0.05 with 2× margin) |
| Each policy-mirror / ignored `react()` | 60–100k | 0.006–0.01 lREACT |

**Lasna lREACT (deployer wallet):** 0.25 (deploy at ceiling) + 2.0 (reactive contract ≈ 40 demo cycles at 0.05) + tx gas ≈ **2.5 minimum; 5 is comfortable (~2× headroom)**. Faucet rate: 1 ETH → 100 lREACT (per tx cap 5 ETH, excess lost), so 5 lREACT = 0.05 ETH.
**Base Sepolia ETH:** faucet request 0.05 + two Guards 0.004 + all gas < 0.001 ≈ **0.06 ETH; hold 0.1 for margin.**
**Correction:** my earlier "0.4 ETH" estimate was not grounded in these numbers — retracted. The dominant Base cost is converting ETH to lREACT, not gas.
Unknowns to measure on the first live run: real gas of `react()` on Lasna (read it on Reactscan) and whether requesting a callback adds a separate Lasna charge (the economy page does not say).

## F. Mainnet safety
- Every deploy script has `require(block.chainid == …)`: Base scripts only on 84532, Lasna only on 5318007. **Tested by simulation:** running the Base scripts against Lasna, the Lasna script against Base Sepolia, and the factory script against Base **mainnet** RPC all revert before any transaction.
- The origin chain (84532) and callback proxy are constants in the scripts, not env-configurable.
- Nothing broadcasts without an explicit `--broadcast`. The signer is an encrypted keystore (`--account`), so no raw key lives in `.env` or on a command line; `preflight.sh` fails if `DEPLOYER_PRIVATE_KEY` appears in `.env`.
- `preflight.sh` also confirms both RPCs report the expected testnet chain IDs.

## G. Exact deployment sequence
Run from `chain_guard/`. Do **not** paste your key anywhere but your own terminal's prompt.

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

# 6. verify (read-only), then run the live loop (sends testnet txs; prints every hash)
cd .. && ./scripts/verify-deployment.sh
./scripts/live-loop.sh
```
`live-loop.sh` does: createGuard (+0.002 ETH) → mint → waits until the policy appears in Lasna state → UNLIMITED approval → polls until allowance is 0 → prints the revoke tx. Then copy the printed hashes and the `RevokeRequested` tx from Reactscan into the README.

Success criteria: `verify-deployment.sh` prints `VERIFY OK`; live loop shows `allowance == 0`; Basescan shows `Approval` (origin), Reactscan shows the `react` tx emitting `RevokeRequested`, Basescan shows `Revoked` from the callback.

**Troubleshooting:** policy never mirrored → reactive unfunded/in debt (`cast balance`), or deployed with wrong `MOCK_ERC20`; approval not revoked → check Reactscan for the `react` tx, then the Guard balance (callback fee) and proxy `debt(guard)`; `Lasna script fails` → try `--legacy` or `--skip-simulation`.

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
