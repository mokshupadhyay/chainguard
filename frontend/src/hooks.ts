import { useQuery } from '@tanstack/react-query'
import { useEffect } from 'react'
import { usePublicClient, useWaitForTransactionReceipt, useWriteContract } from 'wagmi'
import { reportTx } from './api'
import { baseSepolia, lasna } from './config'
import { guardAbi, reactiveAbi } from './abi'

/** Wallet-signed write + receipt tracking. Reports the broadcast hash to the (optional) API. */
export function useTx(label: string, guard?: string, onDone?: () => void) {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract()
  const rc = useWaitForTransactionReceipt({ hash })
  useEffect(() => {
    if (hash) void reportTx(baseSepolia.id, hash, guard ?? '0x0000000000000000000000000000000000000000', label)
  }, [hash]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (rc.isSuccess) onDone?.()
  }, [rc.isSuccess]) // eslint-disable-line react-hooks/exhaustive-deps
  const status = isPending ? 'signing' : hash && rc.isLoading ? 'pending' : rc.isSuccess ? 'confirmed' : rc.isError || error ? 'failed' : 'idle'
  return { send: writeContract, hash, status, error: error?.message.split('\n')[0], reset } as const
}

export interface ChainEvt { kind: 'approved' | 'revoked' | 'reactive'; txHash: `0x${string}`; block: bigint; ts: number; spender: `0x${string}`; value: bigint; chain: 'base' | 'lasna' }

/** Reads Guard events (Base Sepolia) and reactive decisions (Lasna) straight from chain RPCs. */
export function useLoopEvents(guard?: `0x${string}`, reactive?: `0x${string}`) {
  const base = usePublicClient({ chainId: baseSepolia.id })
  const rx = usePublicClient({ chainId: lasna.id })
  return useQuery({
    queryKey: ['loop', guard, reactive],
    enabled: !!guard && !!base,
    refetchInterval: 4000,
    queryFn: async (): Promise<ChainEvt[]> => {
      const out: ChainEvt[] = []
      const ts = async (c: typeof base, b: bigint) => Number((await c!.getBlock({ blockNumber: b })).timestamp)
      const head = await base!.getBlockNumber()
      const fromBlock = head > 8000n ? head - 8000n : 0n
      const [ap, rv] = await Promise.all([
        base!.getContractEvents({ address: guard, abi: guardAbi, eventName: 'Approved', fromBlock }),
        base!.getContractEvents({ address: guard, abi: guardAbi, eventName: 'Revoked', fromBlock }),
      ])
      for (const l of ap.slice(-6)) out.push({ kind: 'approved', chain: 'base', txHash: l.transactionHash, block: l.blockNumber, ts: await ts(base, l.blockNumber), spender: l.args.spender!, value: l.args.amount! })
      for (const l of rv.slice(-6)) out.push({ kind: 'revoked', chain: 'base', txHash: l.transactionHash, block: l.blockNumber, ts: await ts(base, l.blockNumber), spender: l.args.spender!, value: l.args.previousAllowance! })
      if (rx && reactive) {
        try {
          const rh = await rx.getBlockNumber()
          const logs = await rx.getContractEvents({ address: reactive, abi: reactiveAbi, eventName: 'RevokeRequested', args: { guard }, fromBlock: rh > 8000n ? rh - 8000n : 0n })
          for (const l of logs.slice(-6)) out.push({ kind: 'reactive', chain: 'lasna', txHash: l.transactionHash, block: l.blockNumber, ts: await ts(rx, l.blockNumber), spender: l.args.spender!, value: l.args.value! })
        } catch { /* Lasna RPC unavailable: Base-side data still shown */ }
      }
      return out.sort((a, b) => b.ts - a.ts)
    },
  })
}
