import pg from "pg";
import type { EventRow, GuardRow, Store, TxRow, TxStatus } from "./types.js";

const lc = (s?: string | null) => (s ? s.toLowerCase() : s ?? null);

export class MemoryStore implements Store {
  guards = new Map<string, GuardRow>();
  evs = new Map<string, EventRow>();
  tx = new Map<string, TxRow>();
  cursors = new Map<string, number>();
  async upsertGuard(g: GuardRow) { this.guards.set(g.address.toLowerCase(), g); }
  async guardsByOwner(o: string) { return [...this.guards.values()].filter((g) => g.owner.toLowerCase() === o.toLowerCase()); }
  async allGuards() { return [...this.guards.values()]; }
  async insertEvent(e: EventRow) {
    const k = `${e.chainId}:${e.txHash.toLowerCase()}:${e.logIndex}`;
    if (this.evs.has(k)) return false;
    this.evs.set(k, e);
    return true;
  }
  async events({ guard, limit }: { guard?: string; limit: number }) {
    return [...this.evs.values()]
      .filter((e) => !guard || lc(e.guard) === guard.toLowerCase())
      .sort((a, b) => b.blockNumber - a.blockNumber || b.logIndex - a.logIndex)
      .slice(0, limit);
  }
  async upsertTx(t: TxRow) { this.tx.set(`${t.chainId}:${t.txHash.toLowerCase()}`, t); }
  async setTxStatus(c: number, h: string, status: TxStatus, blockNumber?: number) {
    const t = this.tx.get(`${c}:${h.toLowerCase()}`);
    if (t) { t.status = status; t.blockNumber = blockNumber ?? t.blockNumber; }
  }
  async txs({ guard, limit }: { guard?: string; limit: number }) {
    return [...this.tx.values()].filter((t) => !guard || lc(t.guard) === guard.toLowerCase()).slice(0, limit);
  }
  async pendingTxs() { return [...this.tx.values()].filter((t) => t.status === "pending"); }
  async getCursor(k: string) { return this.cursors.get(k) ?? null; }
  async setCursor(k: string, b: number) { this.cursors.set(k, b); }
  async ping() { return true; }
}

const toEvent = (r: any): EventRow => ({
  chainId: Number(r.chain_id), txHash: r.tx_hash, logIndex: r.log_index, blockNumber: Number(r.block_number),
  blockTime: r.block_time ? new Date(r.block_time).toISOString() : null, kind: r.kind,
  guard: r.guard, token: r.token, spender: r.spender, value: r.value, data: r.data,
});
const toTx = (r: any): TxRow => ({
  chainId: Number(r.chain_id), txHash: r.tx_hash, guard: r.guard, label: r.label, status: r.status,
  blockNumber: r.block_number ? Number(r.block_number) : null,
});

export class PgStore implements Store {
  constructor(private pool: pg.Pool) {}
  static fromUrl(url: string) {
    // Supabase requires TLS; the pooler certificate chain is not in Node's default store.
    return new PgStore(new pg.Pool({ connectionString: url, ssl: { rejectUnauthorized: false }, max: 5 }));
  }
  async upsertGuard(g: GuardRow) {
    await this.pool.query(
      `insert into guards(address, owner, chain_id, created_tx_hash, created_block) values($1,$2,$3,$4,$5)
       on conflict (address) do nothing`,
      [g.address.toLowerCase(), g.owner.toLowerCase(), g.chainId, g.createdTxHash ?? null, g.createdBlock ?? null],
    );
  }
  async guardsByOwner(o: string) {
    const r = await this.pool.query(`select * from guards where lower(owner)=lower($1)`, [o]);
    return r.rows.map((x) => ({ address: x.address, owner: x.owner, chainId: Number(x.chain_id), createdTxHash: x.created_tx_hash, createdBlock: x.created_block ? Number(x.created_block) : null }));
  }
  async allGuards() {
    const r = await this.pool.query(`select * from guards`);
    return r.rows.map((x) => ({ address: x.address, owner: x.owner, chainId: Number(x.chain_id) }));
  }
  async insertEvent(e: EventRow) {
    const r = await this.pool.query(
      `insert into events(chain_id, tx_hash, log_index, block_number, block_time, kind, guard, token, spender, value, data)
       values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) on conflict (chain_id, tx_hash, log_index) do nothing`,
      [e.chainId, e.txHash.toLowerCase(), e.logIndex, e.blockNumber, e.blockTime ?? null, e.kind, lc(e.guard), lc(e.token), lc(e.spender), e.value ?? null, JSON.stringify(e.data ?? {})],
    );
    return (r.rowCount ?? 0) > 0;
  }
  async events({ guard, limit }: { guard?: string; limit: number }) {
    const r = guard
      ? await this.pool.query(`select * from events where lower(guard)=lower($1) order by block_number desc, log_index desc limit $2`, [guard, limit])
      : await this.pool.query(`select * from events order by block_number desc, log_index desc limit $1`, [limit]);
    return r.rows.map(toEvent);
  }
  async upsertTx(t: TxRow) {
    await this.pool.query(
      `insert into transactions(chain_id, tx_hash, guard, label, status) values($1,$2,$3,$4,$5)
       on conflict (chain_id, tx_hash) do nothing`,
      [t.chainId, t.txHash.toLowerCase(), lc(t.guard), t.label, t.status],
    );
  }
  async setTxStatus(c: number, h: string, status: TxStatus, blockNumber?: number) {
    await this.pool.query(
      `update transactions set status=$3, block_number=coalesce($4, block_number), updated_at=now() where chain_id=$1 and tx_hash=$2`,
      [c, h.toLowerCase(), status, blockNumber ?? null],
    );
  }
  async txs({ guard, limit }: { guard?: string; limit: number }) {
    const r = guard
      ? await this.pool.query(`select * from transactions where lower(guard)=lower($1) order by created_at desc limit $2`, [guard, limit])
      : await this.pool.query(`select * from transactions order by created_at desc limit $1`, [limit]);
    return r.rows.map(toTx);
  }
  async pendingTxs() {
    return (await this.pool.query(`select * from transactions where status='pending' limit 50`)).rows.map(toTx);
  }
  async getCursor(k: string) {
    const r = await this.pool.query(`select last_block from sync_state where key=$1`, [k]);
    return r.rows[0] ? Number(r.rows[0].last_block) : null;
  }
  async setCursor(k: string, b: number) {
    await this.pool.query(`insert into sync_state(key,last_block) values($1,$2) on conflict (key) do update set last_block=excluded.last_block`, [k, b]);
  }
  async ping() { await this.pool.query("select 1"); return true; }
}
