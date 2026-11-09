# Manual checklist

Last updated: 2026-11-09 (after the deployment-readiness review). Nothing has been deployed or funded.
**Who:** `You` = needs your personal action · `Claude` = I do it (some need your explicit approval first) · `Both`.
**Status:** Pending · In Progress · Completed.
Never paste private keys, seed phrases, passwords or API secrets into chat. Type them only into your own terminal or a provider's dashboard.
Dashboard steps below describe each provider's usual flow; confirm current UI labels and free-tier limits when you get there.

---

## What Claude does automatically (category A)
| Task | Status |
|---|---|
| Contracts + 17 Foundry tests, deploy scripts with chain-ID guards | Completed |
| Backend API + indexer + schema + 10 tests; frontend build/lint | Completed |
| `preflight`, `verify-deployment`, `live-loop`, `install-deps` scripts (syntax-checked, not yet run) | Completed |
| `.env.example` templates, `render.yaml`, Cloudflare SPA fallback, docs | Completed |
| Run the deployment sequence and live loop **after your explicit go** | Pending (needs 1.1–1.6 and 2.1) |
| Record real tx hashes/addresses into README, `DEMO.md`, env templates | Pending (after live loop) |
| Factory-gated dynamic-subscription upgrade, if you choose it (2.2) | Pending (your decision) |
| Re-run all tests/builds before each milestone; update this file | Ongoing |

---

## 1. Wallet and testnet preparation
| # | Task | Why | Who | Instructions | Depends on | Status |
|---|---|---|---|---|---|---|
| 1.1 | Create a **dedicated testnet-only wallet** | Isolates deploy key from any real funds | You | Make a brand-new account in your wallet app (or `cast wallet new`). Never reuse a wallet that holds real assets. Note the **public address** only. | — | Pending |
| 1.2 | Import it into an encrypted **Foundry keystore** | Scripts sign via `--account`; no raw key in `.env` or command lines | You | `cast wallet import chainguard-deployer --interactive` → paste the key and choose a password **at the terminal prompt**. Success: `cast wallet list` shows `chainguard-deployer`. | 1.1 | Pending |
| 1.3 | Install pinned Reactive library | Needed to compile; not committed (license, see 5.3) | You (one command) | `./scripts/install-deps.sh` from `chain_guard/`. Success: prints `installed … @ 3ade0dc…` or `present`. | — | Pending |
| 1.4 | Create `.env` | Local config for scripts | You | `cp .env.example .env`, then set `DEPLOYER_ADDRESS=<public address from 1.1>`. Leave contract addresses blank for now. Do **not** add a private key. | 1.1 | Pending |
| 1.5 | Get **Base Sepolia ETH** (~0.1 ETH) | Deploy gas, 0.002 ETH per Guard, and 0.05 ETH to convert to lREACT | You | Use any Base Sepolia faucet (e.g. a provider faucet or one linked from Base/Coinbase docs) to fund the **public address**. Success: `cast balance $DEPLOYER_ADDRESS --rpc-url https://base-sepolia-rpc.publicnode.com --ether` ≥ 0.1. | 1.4 | Pending |
| 1.6 | Obtain **lREACT** (≥ 2.5, aim ~5) | Lasna gas for deploying and running the reactive contract | You (signs) / Claude can run on request | `set -a; . ./.env; set +a` then `cast send 0x2afaFD298b23b62760711756088F75B7409f5967 "request(address)" $DEPLOYER_ADDRESS --value 0.05ether --rpc-url $BASE_SEPOLIA_RPC --account $DEPLOYER_ACCOUNT`. Re-verify the faucet address on https://dev.reactive.network/reactive-mainnet first. Rate: 1 ETH→100 lREACT. If it doesn't arrive in a few minutes, MetaMask "Smart Transactions" can interfere — use `cast`. Success: `cast balance $DEPLOYER_ADDRESS --rpc-url https://lasna-rpc.rnk.dev/ --ether` ≈ 5. | 1.2, 1.5 | Pending |
| 1.7 | Run `./scripts/preflight.sh` | Read-only gate before any deploy | You (or Claude, if you allow it to read `.env`) | Must end `PREFLIGHT OK`. Fixes are printed per failed check. | 1.2–1.6 | Pending |

## 2. Contract deployment and live testing
| # | Task | Why | Who | Instructions | Depends on | Status |
|---|---|---|---|---|---|---|
| 2.1 | **Explicit go** to deploy and spend testnet funds | Policy: no deployment without your approval | You | Reply with an unambiguous "go" after preflight passes. | 1.7 | Pending |
| 2.2 | Decide: dynamic-subscription upgrade now vs after first live loop | Current wildcard policy subscription lets anyone drain lREACT (see DEPLOYMENT §C) | You decide, Claude implements | Recommended: deploy current contracts first to prove the loop, then upgrade and redeploy (~0.1 lREACT). | — | Pending |
| 2.3 | Deploy token → reactive → fund → factory | Create the contracts | Both | Claude runs DEPLOYMENT §G steps 2–5; **you enter the keystore password** when prompted (or set `KEYSTORE_PASSWORD_FILE` to a 600-permission file outside the repo). Success: three addresses recorded in `.env`. | 2.1 | Pending |
| 2.4 | Verify deployment | Catch wiring mistakes before spending more | Claude | `./scripts/verify-deployment.sh` → `VERIFY OK`. | 2.3 | Pending |
| 2.5 | Run the live loop | The core submission evidence | Both | `./scripts/live-loop.sh` (you enter the keystore password). Success: `allowance == 0`, plus a Basescan approval tx, a Reactscan `react` tx emitting `RevokeRequested`, and a Basescan `Revoked` callback tx. | 2.4 | Pending |
| 2.6 | Record real addresses/hashes in docs | Judges need them | Claude | After 2.5, from the script output only — never invented. | 2.5 | Pending |
| 2.7 | Top up funding before recording | Debt stops delivery | You | Check reactive lREACT and Guard ETH balances the day of the demo; use the commands in DEPLOYMENT §E. | 2.5 | Pending |

## 3. Backend and database configuration
| # | Task | Why | Who | Instructions | Depends on | Status |
|---|---|---|---|---|---|---|
| 3.1 | Create a **Supabase** project | Managed Postgres for the history index | You | supabase.com → New project; set a DB password (store it in a password manager, not chat). Check current free-plan limits and pausing rules. | — | Pending |
| 3.2 | Copy the **Session pooler** connection string | Render needs IPv4-compatible access | You | Dashboard → Project Settings → Database → Connection string → Session pooler. Replace the password placeholder locally. | 3.1 | Pending |
| 3.3 | Apply the schema | Creates tables | Claude runs on your approval, or you | `cd backend && DATABASE_URL='<string>' npm run migrate` → prints `applied 001_init.sql`. Put the string in your shell only, never in a committed file. | 3.2 | Pending |
| 3.4 | Create a **Render** web service | Hosts the Express API | You | render.com → New → Blueprint from your GitHub repo (`render.yaml`), or Web Service: root `backend`, build `npm ci --include=dev && npm run build`, start `npm start`, health check `/health`. | 5.4 | Pending |
| 3.5 | Set Render environment variables | API config/secrets | You | In Render → Environment: `DATABASE_URL`, `CORS_ORIGIN` (your Pages URL once known), `GUARD_FACTORY`, `MOCK_ERC20`, `CHAINGUARD_REACTIVE`, `BASE_START_BLOCK`, `LASNA_START_BLOCK` (deployment blocks, from the broadcast JSON or explorers). Optional: `BASE_SEPOLIA_RPC`. | 2.3, 3.2 | Pending |
| 3.6 | Confirm API health | Proves DB + service | You | Open `https://<service>.onrender.com/health` → `{"ok":true,"db":true}`. First request may take ~1 minute (free tier cold start). | 3.4, 3.5 | Pending |

## 4. Frontend and public hosting
| # | Task | Why | Who | Instructions | Depends on | Status |
|---|---|---|---|---|---|---|
| 4.1 | Create **Cloudflare Pages** project | Hosts the Vite app | You | Cloudflare dashboard → Workers & Pages → Create → Pages → connect GitHub repo. Root directory `frontend`, build command `npm run build`, output `dist`. | 5.4 | Pending |
| 4.2 | Set Pages environment variables (public only) | App needs addresses and API URL | You | `VITE_API_URL` (Render URL), `VITE_MOCK_ERC20`, `VITE_GUARD_FACTORY`, `VITE_CHAINGUARD_REACTIVE`, `VITE_BASE_SEPOLIA_RPC=https://base-sepolia-rpc.publicnode.com`. **No keys or DB strings here.** | 2.3, 3.4 | Pending |
| 4.3 | Point Render CORS at the Pages URL | Browser calls must be allowed | You | Set `CORS_ORIGIN=https://<project>.pages.dev` in Render and redeploy. | 4.1 | Pending |
| 4.4 | Local `frontend/.env` for local testing | Try the UI before publishing | You | `cd frontend && cp .env.example .env`, fill the `VITE_*` addresses, `npm i && npm run dev` → http://localhost:5173 | 2.3 | Pending |

## 5. Security and repository publishing
| # | Task | Why | Who | Instructions | Depends on | Status |
|---|---|---|---|---|---|---|
| 5.1 | Secret scan before first commit | Nothing sensitive may be published | Claude | Targeted scan + `git status`/`git ls-files` review; `.env`, keystores, `broadcast/` are ignored. Already clean as of last review; repeat before publishing. | — | Ongoing |
| 5.2 | Create local commit(s) | Prepare publishable history | Claude, on your request | Commit message with the required attribution. No push. | 5.1 | Pending |
| 5.3 | **Reactive dependency license** question | `reactive-lib-omni` is UNLICENSED everywhere; need written clarity | You | Send the text in DEPLOYMENT §D to Reactive (hackathon organizers / their developer channel, or a GitHub issue on the repo). Keep their reply. Until then the dependency stays un-vendored and git-ignored. | — | Pending |
| 5.4 | Create the **public GitHub repo** and push | Hackathon requires a public repo; hosts deploy from it | You (or Claude with your explicit approval of the exact repo) | Create an empty public repo on GitHub, then `git remote add origin <url> && git push -u origin main`. Confirm `git ls-files` shows no `.env`, no `contracts/lib/reactive-lib-omni`. | 5.1, 5.2 | Pending |
| 5.5 | Add `forge-std` as submodule (optional cleanup) | Avoid vendoring third-party code | Claude | `forge install foundry-rs/forge-std` before the first commit, if you want it. | — | Pending |
| 5.6 | Add `CONTRIBUTING`-style note on cloning | Judges must be able to build | Claude | README already says run `./scripts/install-deps.sh`; re-check after deployment. | — | Completed |

## 6. Manual UI and end-to-end testing
| # | Task | Why | Who | Instructions | Depends on | Status |
|---|---|---|---|---|---|---|
| 6.1 | Local UI test | Claude can't test your browser/wallet UX | You | Follow `docs/DEMO.md` against `localhost:5173` with the deployer or a second testnet wallet. Checks: wrong-network banner; Deploy Guard; Mint; policy shows "active on Lasna ✓"; Approve UNLIMITED → loop steps 1–4 complete → allowance 0; Approve limited → no revoke; backend off → UI still works. | 2.3, 4.4 | Pending |
| 6.2 | Public UI test | Confirms production config | You | Repeat 6.1 on the Pages URL; check browser console for CORS errors; check `/health`. | 4.3 | Pending |
| 6.3 | Report issues | I fix what you find | Both | Send me exact symptoms/screenshots; I fix and re-run the checks. | 6.1 | Pending |

## 7. Hackathon demo and submission
| # | Task | Why | Who | Instructions | Depends on | Status |
|---|---|---|---|---|---|---|
| 7.1 | Final README with real addresses, hashes, URLs | Judges' first page | Claude | After 2.6 and 4.1; actual values only. | 2.6, 4.1 | Pending |
| 7.2 | Record the demo video (< 3:00) | Hard submission requirement | You | Script in `docs/DEMO.md` and the context file §8. Check balances (2.7) first. Record the loop, the three explorer pages, and the allowance before/after. | 6.2 | Pending |
| 7.3 | Submit on DoraHacks | Official entry | You | Hackathon page: https://dorahacks.io/hackathon/reactive-omni-buildathon — track **Set It and Forget It**; repo link, contract addresses, tx hashes, demo video. Deadline per context file: ~5 Dec 2026 20:00 UTC (re-check the page). | 5.4, 7.1, 7.2 | Pending |
| 7.4 | Confirm the repo is public and the loop still works on submission day | Entries without working callbacks aren't scored | You | Open the repo logged out; run one live-loop after topping up (2.7). | 7.3 | Pending |
