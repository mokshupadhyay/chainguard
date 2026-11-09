import { createConfig, fallback, http } from 'wagmi'
import { injected } from 'wagmi/connectors'
import { baseSepolia, cfg, lasna } from './config'

export const wagmiConfig = createConfig({
  chains: [baseSepolia, lasna],
  connectors: [injected()],
  transports: { [baseSepolia.id]: fallback([http(cfg.baseRpc), http('https://base-sepolia.gateway.tenderly.co')]), [lasna.id]: http() },
})
