import { defineChain } from 'viem'
import { baseSepolia } from 'viem/chains'

const env = import.meta.env
const addr = (v?: string) => (v && /^0x[0-9a-fA-F]{40}$/.test(v) ? (v as `0x${string}`) : undefined)

export const lasna = defineChain({
  id: 5318007,
  name: 'Reactive Lasna',
  nativeCurrency: { name: 'Lasna REACT', symbol: 'lREACT', decimals: 18 },
  rpcUrls: { default: { http: ['https://lasna-rpc.rnk.dev/'] } },
  blockExplorers: { default: { name: 'Reactscan', url: 'https://lasna.reactscan.net' } },
})
export { baseSepolia }

export const cfg = {
  api: (env.VITE_API_URL as string | undefined)?.replace(/\/$/, ''),
  baseRpc: (env.VITE_BASE_SEPOLIA_RPC as string | undefined) || 'https://base-sepolia-rpc.publicnode.com',
  token: addr(env.VITE_MOCK_ERC20),
  factory: addr(env.VITE_GUARD_FACTORY),
  reactive: addr(env.VITE_CHAINGUARD_REACTIVE),
}
export const configured = !!(cfg.token && cfg.factory && cfg.reactive)

export const baseTx = (h: string) => `https://sepolia.basescan.org/tx/${h}`
export const baseAddr = (a: string) => `https://sepolia.basescan.org/address/${a}`
export const lasnaTx = (h: string) => `https://lasna.reactscan.net/tx/${h}`
export const lasnaAddr = (a: string) => `https://lasna.reactscan.net/address/${a}`
export const short = (s: string) => `${s.slice(0, 6)}…${s.slice(-4)}`
