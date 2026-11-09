import cors from "cors";
import express, { type NextFunction, type Request, type Response } from "express";
import { z } from "zod";
import type { Store } from "./types.js";

const address = z.string().regex(/^0x[0-9a-fA-F]{40}$/, "invalid address");
const txHash = z.string().regex(/^0x[0-9a-fA-F]{64}$/, "invalid tx hash");
const limitQ = z.coerce.number().int().min(1).max(200).default(50);

export interface AppDeps { store: Store; corsOrigins: string[]; sync?: () => Promise<{ inserted: number }> }

export function createApp({ store, corsOrigins, sync }: AppDeps) {
  const app = express();
  app.use(cors({ origin: corsOrigins }));
  app.use(express.json({ limit: "10kb" }));

  app.get("/health", async (_req, res) => {
    let db = false;
    try { db = await store.ping(); } catch { /* reported below */ }
    res.json({ ok: true, db });
  });

  app.get("/api/guards", async (req, res) => {
    const owner = address.parse(req.query.owner);
    res.json({ guards: await store.guardsByOwner(owner) });
  });

  app.get("/api/events", async (req, res) => {
    const guard = req.query.guard ? address.parse(req.query.guard) : undefined;
    res.json({ events: await store.events({ guard, limit: limitQ.parse(req.query.limit) }) });
  });

  app.get("/api/transactions", async (req, res) => {
    const guard = req.query.guard ? address.parse(req.query.guard) : undefined;
    res.json({ transactions: await store.txs({ guard, limit: limitQ.parse(req.query.limit) }) });
  });

  /** Latest indexed policy + counters for a guard. Informational only: chain state is authoritative. */
  app.get("/api/summary", async (req, res) => {
    const guard = address.parse(req.query.guard);
    const evs = await store.events({ guard, limit: 200 });
    const latestPolicy = evs.find((e) => e.kind === "policy_set");
    res.json({
      guard,
      policy: latestPolicy?.data ?? null,
      counts: {
        approvals: evs.filter((e) => e.kind === "approval_observed").length,
        revokeRequests: evs.filter((e) => e.kind === "revoke_requested").length,
        revocations: evs.filter((e) => e.kind === "revoked").length,
      },
      note: "Indexed data; verify against the chain.",
    });
  });

  /** Frontend reports a tx hash its wallet already broadcast. No keys, no signing here. */
  app.post("/api/transactions", async (req, res) => {
    const body = z.object({
      chainId: z.number().int().positive(), txHash, guard: address.optional(), label: z.string().min(1).max(80),
    }).parse(req.body);
    await store.upsertTx({ ...body, status: "pending" });
    res.status(202).json({ ok: true });
  });

  app.post("/api/sync", async (_req, res) => {
    if (!sync) return res.status(503).json({ error: "indexer not configured" });
    res.json(await sync());
  });

  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof z.ZodError) return res.status(400).json({ error: "validation", issues: err.issues.map((i) => `${i.path.join(".")}: ${i.message}`) });
    console.error(err);
    res.status(500).json({ error: "internal" });
  });
  return app;
}
