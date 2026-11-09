import { cfg } from './config'

export interface ApiEvent { chainId: number; txHash: string; logIndex: number; blockNumber: number; blockTime?: string | null; kind: string; guard?: string; spender?: string; value?: string }
export interface ApiTx { chainId: number; txHash: string; label: string; status: 'pending' | 'confirmed' | 'failed' }

/** The API is optional: every call degrades to null so the core UI never depends on it. */
async function call<T>(path: string, init?: RequestInit): Promise<T | null> {
  if (!cfg.api) return null
  try {
    const r = await fetch(cfg.api + path, { ...init, signal: AbortSignal.timeout(8000) })
    return r.ok ? ((await r.json()) as T) : null
  } catch {
    return null
  }
}
export const fetchEvents = (guard: string) => call<{ events: ApiEvent[] }>(`/api/events?guard=${guard}&limit=50`)
export const fetchTxs = (guard: string) => call<{ transactions: ApiTx[] }>(`/api/transactions?guard=${guard}&limit=50`)
export const reportTx = (chainId: number, txHash: string, guard: string, label: string) =>
  call('/api/transactions', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ chainId, txHash, guard, label }) })
export const triggerSync = () => call('/api/sync', { method: 'POST' })
