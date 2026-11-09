# 🛡️ ChainGuard

Track: **Set It and Forget It** (Reactive Omni Buildathon).

A reactive on-chain watchdog for token approvals. Your **Guard** (a vault you own on Base Sepolia) holds your tokens. A **reactive contract on Reactive Lasna** watches approvals, evaluates your policy inside `react()`, and — when a dangerous (e.g. unlimited) approval appears — triggers a callback that makes the Guard revoke it. No keeper bot.

> **Honest scope:** ChainGuard cannot revoke approvals for a plain EOA. Tokens live in your Guard, which is the approver.

## Status
| Item | State |
|---|---|
| Contracts + Foundry tests (36) | ✅ passing locally |
| Backend API (9 tests) / Frontend build | ✅ passing locally |
| Testnet deployment & live loop | ⏳ **not yet done** |
| Contract addresses / tx hashes | _none yet — will be added only from real deployments_ |
| Public URL | _pending_ |

## Architecture
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Flow: factory `GuardCreated` registers the Guard on Lasna (runtime, Guard-scoped subscriptions) → `approve` → Reactive event detection → `react()` policy decision → callback via Base Sepolia proxy → `Guard.revoke` → `approve(spender, 0)`.

## Stack
Solidity + Foundry · Vite/React/TS/Tailwind/wagmi/viem · Express/TS/Zod · Supabase Postgres · Cloudflare Pages + Render.

## Local setup
```bash
cp .env.example .env            # fill in later; never commit
./scripts/install-deps.sh       # pinned reactive-lib-omni (not vendored; see docs/DEPLOYMENT.md §D)
cd contracts && forge test      # 36 tests
cd ../backend && npm i && npm test && npm run dev     # in-memory store if DATABASE_URL unset
cd ../frontend && cp .env.example .env && npm i && npm run dev   # http://localhost:5173
```
Tests/checks: `forge test`; backend `npm run typecheck && npm run lint && npm test && npm run build`; frontend `npm run build && npm run lint`.

## Deploy / demo
[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) · [docs/DEMO.md](docs/DEMO.md)

## Contract addresses & explorers
_To be filled from real deployments._ Explorers: [Basescan Sepolia](https://sepolia.basescan.org) · [Reactscan Lasna](https://lasna.reactscan.net)

License: MIT for this repository's own code. `reactive-lib-omni` (Reactive Network) is a separate dependency with no published license; it is not redistributed here.
