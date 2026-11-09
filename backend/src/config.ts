import "dotenv/config";
import { z } from "zod";

const addr = z.string().regex(/^0x[0-9a-fA-F]{40}$/);
const schema = z.object({
  PORT: z.coerce.number().default(8787),
  CORS_ORIGIN: z.string().default("http://localhost:5173"), // comma-separated
  DATABASE_URL: z.string().optional(),
  BASE_SEPOLIA_RPC: z.string().default("https://base-sepolia-rpc.publicnode.com"),
  LASNA_RPC: z.string().default("https://lasna-rpc.rnk.dev/"),
  GUARD_FACTORY: addr.optional(),
  MOCK_ERC20: addr.optional(),
  CHAINGUARD_REACTIVE: addr.optional(),
  BASE_START_BLOCK: z.coerce.number().optional(),
  LASNA_START_BLOCK: z.coerce.number().optional(),
  INDEXER_INTERVAL_MS: z.coerce.number().default(15000),
});
export const loadConfig = () => schema.parse(process.env);
export type Config = z.infer<typeof schema>;
export const BASE_SEPOLIA = 84532;
export const LASNA = 5318007;
