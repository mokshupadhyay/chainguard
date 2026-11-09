import { createPublicClient, defineChain, http } from "viem";
import { baseSepolia } from "viem/chains";
import { createApp } from "./app.js";
import { loadConfig, LASNA } from "./config.js";
import { syncAll } from "./indexer.js";
import { MemoryStore, PgStore } from "./store.js";

const cfg = loadConfig();
const store = cfg.DATABASE_URL ? PgStore.fromUrl(cfg.DATABASE_URL) : new MemoryStore();
if (!cfg.DATABASE_URL) console.warn("DATABASE_URL not set: using in-memory store (dev only)");

const lasna = defineChain({
  id: LASNA, name: "Reactive Lasna", nativeCurrency: { name: "Lasna REACT", symbol: "lREACT", decimals: 18 },
  rpcUrls: { default: { http: [cfg.LASNA_RPC] } },
});
const clients = {
  base: createPublicClient({ chain: baseSepolia, transport: http(cfg.BASE_SEPOLIA_RPC) }),
  lasna: createPublicClient({ chain: lasna, transport: http(cfg.LASNA_RPC) }),
};

let running: Promise<{ inserted: number }> | null = null;
const sync = () => (running ??= syncAll(store, cfg, clients).finally(() => { running = null; }));

createApp({ store, corsOrigins: cfg.CORS_ORIGIN.split(","), sync }).listen(cfg.PORT, () => console.log(`api on :${cfg.PORT}`));

// Background indexing. If this fails or the DB is down, on-chain protection is unaffected.
setInterval(() => sync().catch((e) => console.error("sync failed:", e.message)), cfg.INDEXER_INTERVAL_MS);
