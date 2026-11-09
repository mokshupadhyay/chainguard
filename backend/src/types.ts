export type EventKind =
  | "guard_created" | "policy_set" | "approved" | "revoked" | "approval_observed"
  | "policy_mirrored" | "revoke_requested" | "approval_ignored" | "guard_registered";

export interface EventRow {
  chainId: number;
  txHash: string;
  logIndex: number;
  blockNumber: number;
  blockTime?: string | null;
  kind: EventKind;
  guard?: string | null;
  token?: string | null;
  spender?: string | null;
  value?: string | null; // uint256 as decimal string
  data?: Record<string, unknown>;
}
export interface GuardRow { address: string; owner: string; chainId: number; createdTxHash?: string | null; createdBlock?: number | null }
export type TxStatus = "pending" | "confirmed" | "failed";
export interface TxRow { chainId: number; txHash: string; guard?: string | null; label: string; status: TxStatus; blockNumber?: number | null }

export interface Store {
  upsertGuard(g: GuardRow): Promise<void>;
  guardsByOwner(owner: string): Promise<GuardRow[]>;
  allGuards(): Promise<GuardRow[]>;
  /** returns true when a new row was inserted, false when it already existed (idempotent). */
  insertEvent(e: EventRow): Promise<boolean>;
  events(opts: { guard?: string; limit: number }): Promise<EventRow[]>;
  upsertTx(t: TxRow): Promise<void>;
  setTxStatus(chainId: number, txHash: string, status: TxStatus, blockNumber?: number): Promise<void>;
  txs(opts: { guard?: string; limit: number }): Promise<TxRow[]>;
  pendingTxs(): Promise<TxRow[]>;
  getCursor(key: string): Promise<number | null>;
  setCursor(key: string, block: number): Promise<void>;
  ping(): Promise<boolean>;
}
