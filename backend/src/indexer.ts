import { erc20ApprovalAbi } from "./abi.js";
import { BASE_SEPOLIA, LASNA, type Config } from "./config.js";
import { decodeLog } from "./decode.js";
import type { Store } from "./types.js";

const CHUNK = 2000n;

export interface Clients { base: any; lasna: any }

/** Index one chain's range. Idempotent: events are keyed by (chain_id, tx_hash, log_index). */
async function scan(store: Store, client: any, chainId: number, key: string, startBlock: number | undefined,
  fetchLogs: (from: bigint, to: bigint) => Promise<any[]>): Promise<number> {
  const head = await client.getBlockNumber();
  const cur = await store.getCursor(key);
  let from = cur != null ? BigInt(cur) + 1n : BigInt(startBlock ?? Number(head > 5000n ? head - 5000n : 0n));
  let inserted = 0;
  const times = new Map<bigint, string>();
  while (from <= head) {
    const to = from + CHUNK - 1n > head ? head : from + CHUNK - 1n;
    for (const log of await fetchLogs(from, to)) {
      let t = times.get(log.blockNumber);
      if (!t) {
        const b = await client.getBlock({ blockNumber: log.blockNumber });
        t = new Date(Number(b.timestamp) * 1000).toISOString();
        times.set(log.blockNumber, t);
      }
      const row = decodeLog(chainId, log, t);
      if (!row) continue;
      if (row.kind === "guard_created") {
        await store.upsertGuard({ address: row.guard!, owner: String(row.data?.owner), chainId, createdTxHash: row.txHash, createdBlock: row.blockNumber });
        // A new guard may have emitted events in blocks other scans already passed: rewind them (inserts are idempotent).
        for (const k of ["base:guards", "base:token"]) {
          const c = await store.getCursor(k);
          if (c != null && c >= row.blockNumber) await store.setCursor(k, row.blockNumber - 1);
        }
      }
      if (await store.insertEvent(row)) inserted++;
    }
    await store.setCursor(key, Number(to)); // only advance after the range is fully stored
    from = to + 1n;
  }
  return inserted;
}

export async function syncAll(store: Store, cfg: Config, c: Clients): Promise<{ inserted: number }> {
  let inserted = 0;
  if (cfg.GUARD_FACTORY) {
    inserted += await scan(store, c.base, BASE_SEPOLIA, "base:factory", cfg.BASE_START_BLOCK,
      (fromBlock, toBlock) => c.base.getLogs({ address: cfg.GUARD_FACTORY as `0x${string}`, fromBlock, toBlock }));
  }
  const guards = (await store.allGuards()).map((g) => g.address as `0x${string}`);
  if (guards.length) {
    inserted += await scan(store, c.base, BASE_SEPOLIA, "base:guards", cfg.BASE_START_BLOCK,
      (fromBlock, toBlock) => c.base.getLogs({ address: guards, fromBlock, toBlock }));
    if (cfg.MOCK_ERC20) {
      inserted += await scan(store, c.base, BASE_SEPOLIA, "base:token", cfg.BASE_START_BLOCK,
        (fromBlock, toBlock) => c.base.getLogs({ address: cfg.MOCK_ERC20 as `0x${string}`, event: erc20ApprovalAbi[0], args: { owner: guards }, fromBlock, toBlock }));
    }
  }
  if (cfg.CHAINGUARD_REACTIVE) {
    inserted += await scan(store, c.lasna, LASNA, "lasna:reactive", cfg.LASNA_START_BLOCK,
      (fromBlock, toBlock) => c.lasna.getLogs({ address: cfg.CHAINGUARD_REACTIVE as `0x${string}`, fromBlock, toBlock }));
  }
  await resolvePending(store, c);
  return { inserted };
}

/** pending -> confirmed | failed, from the real receipt. */
export async function resolvePending(store: Store, c: Clients) {
  for (const t of await store.pendingTxs()) {
    const client = t.chainId === LASNA ? c.lasna : c.base;
    try {
      const r = await client.getTransactionReceipt({ hash: t.txHash as `0x${string}` });
      await store.setTxStatus(t.chainId, t.txHash, r.status === "success" ? "confirmed" : "failed", Number(r.blockNumber));
    } catch { /* not mined yet: leave pending */ }
  }
}
