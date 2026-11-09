# 3-minute demo (UI)
1. Connect wallet on Base Sepolia. Click **Deploy Guard** (confirm in wallet).
2. Click **Mint 1,000 demo tokens into Guard**.
3. Wait until the policy card says **Policy active on Reactive Lasna ✓**.
4. Click **Approve UNLIMITED** (spender prefilled). Allowance turns red (UNLIMITED).
5. Watch **Reactive loop status**: approval → react() decision on Lasna → callback → allowance 0. Open each explorer link.
6. Try **Approve limited** (100): no revoke — the policy only targets unlimited.

Expected hashes: _to be filled after the first live run (none recorded yet)._
