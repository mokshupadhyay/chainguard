# Progress record (updated 2026-11-09)
**Done & verified locally:** contracts (17 forge tests), deploy scripts with chain-ID guards (simulated on live Base Sepolia / Lasna state; wrong-chain and mainnet attempts revert), backend (10 tests, typecheck/lint/build), frontend (build/lint), ops scripts (`preflight`, `verify-deployment`, `live-loop`, `install-deps` — syntax-checked only, not executed), docs.
**Not done:** any deployment, funding, live loop, Supabase migration run, hosting, license confirmation from Reactive.

**Verified this round** (details in docs/DEPLOYMENT.md): Omni API usage matches docs/lib; deployment order & constructor deps; runtime subscriptions are supported (our static design was a deliberate-but-unverified MVP choice, with an lREACT-drain weakness via wildcard policy subscription); `reactive-lib-omni` has no license (UNLICENSED everywhere) → not vendored, git-ignored, installed by pinned script; budget recomputed (≈0.06 ETH Base, ≈2.5–5 lREACT; earlier 0.4 ETH retracted); scripts hard-fail off-testnet; signer moved to encrypted keystore (no raw key in .env).
**Fixed earlier:** Base public RPC getLogs cap (→ publicnode), indexer new-guard cursor race, Render devDeps build.

**Open decisions for the user:** (1) ship current static subscription for the first live loop, then upgrade to factory-gated dynamic subscriptions (recommended) vs. upgrade before first deploy; (2) send the license question to Reactive.
**Next:** user does setup in DEPLOYMENT.md §G step 0 → preflight → explicit go → deploy.
