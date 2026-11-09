# ChainGuard — Builder Context (Reactive Omni Buildathon)

**Project name:** ChainGuard  
**Hackathon track:** Set It and Forget It  
**Product one-liner:** A personal approval watchdog that auto-revokes dangerous token allowances on-chain, with no off-chain bot.

This file is the full brief for anyone starting cold. Read it end to end before writing code.

---

## 1. Hackathon overview (read first)

| Item | Detail |
|------|--------|
| Event | **Reactive Omni Buildathon** |
| Organiser | Reactive Network via **DoraHacks** |
| Format | Virtual / online |
| Build window | ~5 Nov 2026 → deadline **6 Dec 2026, 01:30 IST** (DoraHacks: **5 Dec 2026 ~20:00 UTC**) |
| Prize pool | **$5,500 USD**, paid in **REACT** |
| Our track prize | Set It and Forget It: **$2,000** first, **$250** runner-up |
| Other tracks (do not submit ChainGuard here) | Every Second Counts ($2k/$250), Reactive Meets AI ($1k first) |

### Official links

- Hackathon page: https://dorahacks.io/hackathon/reactive-omni-buildathon  
- Reactive docs (start here): https://dev.reactive.network/  
- Mainnet origins/destinations: https://dev.reactive.network/origins-and-destinations#mainnet-chains  
- Testnet origins/destinations: https://dev.reactive.network/origins-and-destinations#testnet-chains  
- Reactive blog / track brief (useful for wording): https://blog.reactive.network/reactive-omni-buildathon-thirty-days-to-find-out-what-one-second-buys/

### What Reactive Omni is (plain language)

A **reactive contract** is a Solidity contract that lives on **Reactive Network** (testnet name: **Lasna**). It **subscribes to event logs** on other EVM chains (e.g. Base Sepolia). When a matching log appears, the system calls `react(...)`. Your logic can update state and ask the system to **send a callback transaction** to a contract on a destination chain (often the same chain the event came from).

Roles:

1. **Origin** — chain that emits the event you watch (for us: Base Sepolia).  
2. **Reactive (Lasna)** — where ChainGuard’s reactive policy contract lives and decides.  
3. **Destination** — chain where the callback runs and state changes (for us: Base Sepolia again).

Omni specifics that matter:

- ~**1 second** blocks + **instant finality** on Reactive.  
- Use modern Omni patterns: `onlySystem`, system contract at `0x8888…8888`.  
- Callbacks via `SYSTEM.requestCallbackV_1_0({ chainId, recipient, gasLimit, payload })`.  
- **First 160 bits of the callback payload are overwritten** with the reactive contract address. Always declare `address` as the **first** argument of the destination function and pass `address(0)` as a placeholder when encoding.  
- Keep the **reactive contract funded in lREACT** (pays reactive txs) and the **destination contract funded in destination native gas** (pays callbacks). Debt stops delivery.  
- On **Base Sepolia**, blocks are ~**200ms**. Use **timestamps** (or event counts you control), **not block-number deltas**, for any timers/cooldowns.

### Testnets we use

| Chain | Role | Chain ID | Notes |
|-------|------|----------|-------|
| **Base Sepolia** | Origin + destination | `84532` | Callback proxy (check docs for latest): often listed as `0x476F44b11F5C942c58f4c8E3d0300E5710743585`. Verify on docs before hardcoding. |
| **Reactive Lasna** | Reactive contracts | `5318007` | RPC: `https://lasna-rpc.rnk.dev/` · Explorer: `https://lasna.reactscan.net/` · System: `0x8888…8888` |

Faucet pattern (confirm on docs if amounts change): send Sepolia ETH to a Reactive faucet address to receive **lREACT** (examples seen in docs: Base Sepolia faucet `0x2afaFD298b23b62760711756088F75B7409f5967` or Ethereum Sepolia `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434` — **re-verify on https://dev.reactive.network/ before use**).

We do **not** need Unichain for ChainGuard MVP. Stay on Base Sepolia + Lasna.

---

## 2. What we are building: ChainGuard

### Problem

Users (and dapps) grant ERC-20 `approve(spender, amount)`. Unlimited or oversized allowances are a common drain vector. Today people rely on dashboards, browser extensions, or manual revoke. Those need attention. ChainGuard is a **set once, leave running** personal automation: when a dangerous approval appears for your watched wallet, it **revokes on-chain automatically**.

### Product definition (MVP)

**ChainGuard** = user-owned **Guard module** on Base Sepolia + **Reactive policy contract** on Lasna + a small **Next.js** control panel.

Happy path demo (&lt; 3 minutes):

1. User connects wallet, deploys/registers their **Guard** (or uses a factory).  
2. User sets policy: e.g. “revoke any `type(uint256).max` approval for my address” and/or “revoke if allowance &gt; X”.  
3. Demo token: user (or script) calls `approve(maliciousSpender, max)`.  
4. Lasna reactive contract sees `Approval`, matches owner + policy.  
5. Callback hits Guard → `token.approve(spender, 0)` (or Guard’s revoke helper).  
6. UI shows: origin Approval tx → reactive tx → callback revoke tx, with explorer links.

### What ChainGuard is NOT

- Not a Crebit / company product integration. Standalone hackathon system.  
- Not Every Second Counts (do not pitch latency as the main story).  
- Not “AI wrote my contracts” (wrong track).  
- Not a dumb event forwarder: **policy must live in `react()`**.  
- Not claiming it can revoke approvals for a plain EOA with no opt-in module. **Users must authorize a Guard** that can call `approve(0)` on their behalf (owner-controlled module, or tokens held/wrapped by the module — see auth section).

### Track alignment

Submit under **Set It and Forget It**:

- Personal automation  
- No contract experience required *for the end user story* (UI does deploy/policy)  
- Sleep-safety &gt; millisecond PnL  

Omni’s 1s blocks are a bonus for snappy revoke, not the headline. Headline = **policy runs without a keeper bot**.

---

## 3. Judging criteria (optimize for these)

Scores are **1–5**, four criteria **equally weighted**. Official rule: entries **without reactive transactions and the callbacks they trigger are not scored further**.

| Criterion | What judges want | How ChainGuard wins |
|-----------|------------------|---------------------|
| **Execution** | It runs. Show reactive txs + on-chain callbacks. | Funded contracts, reproducible loop, three clean hash triples in README + demo. |
| **Integration** | Reactive contract does **real work**, not bolted on. | `react()` filters owner, evaluates unlimited/over-cap policy, then requests revoke callback. Not `emit → forward`. |
| **Usefulness** | Solves a real user problem. | Unlimited approvals → auto-zero is instantly legible. Setup must be &lt;2 minutes in the video. |
| **Craft** | Readable code, working demo &lt;3 min, docs someone else can follow. | Clean monorepo, Foundry tests, Next.js UI, architecture diagram, copy-paste repro. |

### Predicted bar if shipped clean

Rough judge model used in planning: **~4.5 overall** (E 4.5 · I 4.5 · U 4.5 · C 4.5) on Set It, **if** Guard auth works live. This is **not guaranteed**. Fail the Guard module and Usefulness/Execution collapse.

### Failure modes that kill the score

1. Callback cannot revoke because there is no authorized Guard (EOA-only dream).  
2. `react()` is a dumb relay with policy only in the UI.  
3. Unfunded Lasna / destination → callbacks stop mid-demo.  
4. Private repo or missing tx hashes / demo video.  
5. Docs that only the author understands.

---

## 4. Submission requirements (hard gates)

From the hackathon page. Submit on DoraHacks with:

1. **Public** GitHub / GitLab / Bitbucket link (open source by submit time).  
2. **Deployed contract addresses** (Base Sepolia Guard + token if any; Lasna reactive).  
3. **Transaction hashes** showing the **full loop**: origin event → reactive → callback.  
4. **Demo video under 3 minutes**.

Ground rules:

- Repo public and open-source at submit.  
- Built during the event; prior work OK as **dependency**, not as the submission itself.  
- Base Sepolia: timestamps not block counts for timers.

Suggested LICENSE: MIT.

---

## 5. Architecture

### Components

```
[User wallet] 
    │
    ├─ deploys/owns GuardModule (Base Sepolia)
    ├─ sets policy via UI → written to ReactivePolicy (Lasna) and/or Guard
    └─ (demo) approves MockERC20 → malicious spender

[MockERC20] --Approval(owner,spender,value)--> logs on Base Sepolia
                      │
                      ▼
        Reactive Network subscription (Lasna)
                      │
                      ▼
        ChainGuardReactive.react(LogRecord)
           - decode Approval
           - if owner is protected user
           - if policy says dangerous
           - SYSTEM.requestCallbackV_1_0 → GuardModule.revoke(...)
                      │
                      ▼
        GuardModule on Base Sepolia
           - onlyCallbackSender / onlyServiceProvider checks
           - token.approve(spender, 0)  // or decreaseAllowance pattern
           - emit Revoked(...)
                      │
                      ▼
        Next.js dashboard shows latency + 3 explorers
```

### Suggested contracts

| Contract | Chain | Responsibility |
|----------|-------|----------------|
| `MockERC20` | Base Sepolia | Demo token with standard `Approval` events. |
| `GuardModule` (or `ChainGuardSafe`) | Base Sepolia | User-owned. Authorized to revoke allowances for tokens the design supports. Emits `Revoked`. Accepts callbacks only from Reactive callback path. |
| `GuardFactory` (optional) | Base Sepolia | One-click deploy Guard for `msg.sender`. |
| `ChainGuardReactive` | Lasna | Subscribes to `Approval` (topic0). Stores per-user policy. `react()` decides. Requests callback. |

### Auth design (critical — day 1 decision)

Plain EOAs cannot have a third party call `token.approve` for them. Pick **one** MVP pattern and stick to it:

**Recommended MVP (simplest demo):**

- User deploys `GuardModule`.  
- Demo flow uses tokens **held by the Guard** (user deposits mock USDC into Guard), and approvals are from **Guard as owner**. Reactive revokes Guard’s approvals.  
- UI copy: “Deposit into your Guard vault; ChainGuard watches approvals from your Guard.”  
- This is honest and demoable. Do not claim magic EOA revoke.

**Alternative (harder, more “wallet”):**

- Guard is a module the user’s smart account / Safe enables; callback calls into the account’s revoke function. Only do this if you already know Safe/module tooling; otherwise it burns the calendar.

**Do not** ship a design that “calls approve(0) on behalf of a random EOA.” It will fail Execution/Usefulness.

### Policy model (MVP)

Store per user (address → policy) on Lasna (and mirror display in UI):

```text
revokeUnlimited: bool          // true → revoke when value == type(uint256).max
maxAllowance: uint256          // revoke when value > maxAllowance (0 = disabled)
enabled: bool
// optional v2: token allowlist/denylist, spender denylist
```

`react()` logic (pseudocode):

```text
decode Approval(owner, spender, value)
if !policies[owner].enabled: return
if policies[owner].revokeUnlimited && value == MAX: requestRevoke
else if maxAllowance > 0 && value > maxAllowance: requestRevoke
else: return
```

Integration score needs this decision **on Lasna**, not only in the frontend.

### Callback payload discipline

Destination function shape (illustrative):

```solidity
function revoke(address /* reactiveSender */, address token, address spender) external;
```

When encoding from Lasna, first arg placeholder `address(0)`; system overwrites with reactive address. Guard must verify the caller is the Reactive **callback/proxy** path (follow latest Reactive docs for `onlyCallback` / service provider checks). Copy patterns from official Reactive examples; do not invent auth.

---

## 6. Tech stack

| Layer | Choice |
|-------|--------|
| Smart contracts | Solidity 0.8.x + **Foundry** |
| Reactive | Official Reactive libraries / interfaces from docs + examples |
| Frontend | **Next.js** + TypeScript + wagmi/viem |
| Networks | Base Sepolia + Lasna |
| Repo | Monorepo: `/contracts`, `/app` (or `/frontend`), `/docs` |
| Tests | Foundry unit tests for Guard policy helpers; fork/mock tests where possible |
| Lint/format | forge fmt + prettier/eslint on app |

Avoid Uniswap V3, Permit2 complexity, and multi-chain origins in MVP. Optional post-MVP: SpendLatch-style cumulative session budgets (out of scope unless core loop is done).

---

## 7. Repo layout (suggested)

```text
chainguard/
  README.md                 # judges land here
  LICENSE
  docs/
    ARCHITECTURE.md
    DEMO.md                 # click-by-click + expected hashes placeholders
    JUDGING.md              # map features → criteria (optional short)
  contracts/
    src/
      MockERC20.sol
      GuardModule.sol
      GuardFactory.sol      # optional
      reactive/
        ChainGuardReactive.sol
    test/
    script/
      DeployBase.s.sol
      DeployLasna.s.sol
      DemoApprove.s.sol
    foundry.toml
  app/                      # Next.js
    src/app/...
    ...
```

---

## 8. README / Craft checklist (write for a stranger)

README must include:

1. One-paragraph pitch + track name.  
2. Architecture diagram (mermaid OK).  
3. Deployed addresses table.  
4. Example full-loop tx hashes (origin, reactive, callback) with explorer links.  
5. How to run locally (forge test, next dev).  
6. How to reproduce the demo on testnets (faucet → deploy → set policy → approve → observe revoke).  
7. Env vars template (RPC URLs, private key **never committed**).  
8. Short “Why Reactive” blurb: on-chain automation without a keeper; policy in `react()`.  

Demo video script (&lt;3 min):

1. 0:00–0:20 Problem (unlimited approve risk).  
2. 0:20–0:50 Open UI, show Guard + policy “revoke unlimited”.  
3. 0:50–1:40 Trigger malicious unlimited approve; wait for revoke.  
4. 1:40–2:20 Show three explorer txs + allowance now 0.  
5. 2:20–2:50 Point at reactive decision in code/README.  
6. End. No fluff.

---

## 9. Build plan (evenings, ~2–3 weeks)

Adjust to your calendar; deadline ~5–6 Dec 2026.

| Phase | Focus | Done when |
|-------|--------|-----------|
| **Day 1** | Auth design locked (Guard-as-owner MVP). Skeleton Foundry repo. Read Reactive callback examples end to end. | Design 1-pager in `docs/ARCHITECTURE.md` |
| **Days 2–4** | `MockERC20` + `GuardModule` + local tests for revoke path (simulate callback sender). | forge test green |
| **Days 5–8** | `ChainGuardReactive` subscribe + `react` policy + callback encode. Deploy Lasna + Base Sepolia. Fund lREACT + gas. | First live hash triple |
| **Days 9–12** | Next.js: connect, deploy/register Guard, set policy, trigger demo approve, status panel + explorers. | Click-through demo |
| **Days 13–15** | Polish: latency display (timestamps), README, DEMO.md, video, edge cases (already-zero, non-matching owner). | Submit-ready |
| **Buffer** | Faucet issues, proxy address updates from docs, video re-record. | — |

Do **not** start Permit2/session SpendLatch until the unlimited-approve loop is solid on-chain.

---

## 10. Rules and policies to maintain (team discipline)

### Product policies

1. Standalone hackathon product named **ChainGuard**. No company branding.  
2. Submit track = **Set It and Forget It** only.  
3. Honesty in copy: Guard opt-in required; no “protects any EOA magically.”  
4. Prefer one chain pair: Base Sepolia ↔ Lasna.  

### Engineering policies

1. Public repo from early on (or open before submit; earlier is safer for Craft).  
2. No secrets in git. Use `.env.example`.  
3. Every callback destination function: `address` first param for reactive overwrite.  
4. Verify callback auth against Reactive docs every time you upgrade interfaces.  
5. Keep reactive + destination wallets funded before any demo recording.  
6. Use timestamps on Base Sepolia, never block-delta timers.  
7. Foundry tests for policy helpers before mainnet-testnet “hope.”  
8. Scope freeze: MVP = unlimited (+ optional max cap). No NFT, no bridge, no AI track features.  

### Judging-oriented policies

1. Every PR/feature ask: “Does this improve Execution, Integration, Usefulness, or Craft?” If no, cut.  
2. Integration litmus: if you removed Lasna and a centralized bot could replace it with the same UX pitch, strengthen what `react()` decides.  
3. Demo must show **allowance before = max, after = 0** on-chain, not only UI state.  
4. Capture hashes the same day the demo works; explorers and faucets drift.  
5. Video ≤ 3:00. Hard cut.  

### Collaboration / quality bar

1. Prefer small vertical slices (one working loop) over wide unfinished surface.  
2. Document proxy addresses and chain IDs with a “verified on DATE from URL” note.  
3. If docs disagree with blog examples, **docs win**; re-check https://dev.reactive.network/  

---

## 11. Environment variables (template)

```bash
# Base Sepolia
BASE_SEPOLIA_RPC=
BASE_SEPOLIA_PRIVATE_KEY=
BASE_SEPOLIA_CHAIN_ID=84532

# Lasna
LASNA_RPC=https://lasna-rpc.rnk.dev/
LASNA_PRIVATE_KEY=
LASNA_CHAIN_ID=5318007

# Deployed (fill after deploy)
MOCK_ERC20=
GUARD_MODULE=
GUARD_FACTORY=
CHAINGUARD_REACTIVE=

# App
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=
NEXT_PUBLIC_BASE_SEPOLIA_RPC=
```

---

## 12. Definition of done (submit)

- [ ] Public OSS repo with MIT (or similar)  
- [ ] Contracts deployed; addresses in README  
- [ ] At least one full-loop hash triple verified on explorers  
- [ ] Next.js demo path works for a teammate on a clean machine  
- [ ] Demo video &lt; 3 min uploaded / linked  
- [ ] DoraHacks submission: track **Set It and Forget It**, all fields filled  
- [ ] Reactive contract funded; callback still works day-of-submit  

---

## 13. Stretch (only after MVP)

1. Spender denylist.  
2. Token allowlist.  
3. SpendLatch-style cumulative session budget (separate policy type).  
4. Optional second origin chain (skip unless spare days).  
5. Formal security notes (reentrancy, callback spoofing checklist).  

---

## 14. Quick glossary

| Term | Meaning |
|------|---------|
| Reactive contract | Contract on Lasna that reacts to cross-chain logs |
| Callback | Tx Reactive requests on a destination chain |
| lREACT | Gas/token used to pay reactive execution on Lasna |
| Guard / GuardModule | User-owned Base contract ChainGuard controls for revokes |
| Set It and Forget It | Our DoraHacks track: personal automations |
| ESC | Every Second Counts — different track; not our submission |

---

## 15. Contact with planning docs (same Agent Store)

If available in your Context folder:

- Idea scorecard: `docs/reactive-omni-idea-scorecard.md` (AllowGuard row)  
- Beyond-top ideas: `docs/reactive-omni-ideas-beyond-top.md` (SpendLatch as cousin, not MVP)  
- Older ESC plan (LockGuard/FlashExit): `docs/reactive-omni-build-plan.md` — **historical; do not build that for this submission**

---

**Bottom line for builders:** Ship a boring, reliable unlimited-approve → Lasna policy → on-chain revoke loop with a clear Guard opt-in story, a sharp &lt;3 min video, and a README a judge can reproduce. That is how ChainGuard maximizes score on Set It and Forget It.
