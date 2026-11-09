import { encodeAbiParameters, encodeEventTopics } from "viem";
import request from "supertest";
import { describe, expect, it } from "vitest";
import { factoryAbi, guardAbi, reactiveAbi } from "../src/abi.js";
import { createApp } from "../src/app.js";
import { decodeLog } from "../src/decode.js";
import { MemoryStore } from "../src/store.js";

const A = "0x1111111111111111111111111111111111111111";
const G = "0x2222222222222222222222222222222222222222";
const T = "0x3333333333333333333333333333333333333333";
const H = "0x" + "ab".repeat(32);
const mk = () => { const store = new MemoryStore(); return { store, app: createApp({ store, corsOrigins: ["*"] }) }; };

describe("decodeLog", () => {
  it("decodes Revoked from a guard", () => {
    const topics = encodeEventTopics({ abi: guardAbi, eventName: "Revoked", args: { token: T, spender: A } });
    const data = encodeAbiParameters([{ type: "uint256" }], [123n]);
    const r = decodeLog(84532, { topics, data, transactionHash: H, logIndex: 3, blockNumber: 10n, address: G } as any);
    expect(r).toMatchObject({ kind: "revoked", guard: G, token: T, spender: A, value: "123", logIndex: 3 });
  });
  it("decodes RevokeRequested from the reactive contract", () => {
    const topics = encodeEventTopics({ abi: reactiveAbi, eventName: "RevokeRequested", args: { guard: G, token: T, spender: A } });
    const data = encodeAbiParameters([{ type: "uint256" }, { type: "string" }], [2n ** 256n - 1n, "unlimited"]);
    const r = decodeLog(5318007, { topics, data, transactionHash: H, logIndex: 0, blockNumber: 1n, address: A } as any);
    expect(r).toMatchObject({ kind: "revoke_requested", value: (2n ** 256n - 1n).toString(), data: { reason: "unlimited" } });
  });
  it("ignores unknown logs", () => {
    expect(decodeLog(1, { topics: ["0x" + "00".repeat(32)], data: "0x", transactionHash: H, logIndex: 0, blockNumber: 1n, address: A } as any)).toBeNull();
  });
});

describe("store idempotency", () => {
  it("inserts a (chain, tx, logIndex) once", async () => {
    const s = new MemoryStore();
    const e = { chainId: 1, txHash: H, logIndex: 0, blockNumber: 1, kind: "revoked" as const };
    expect(await s.insertEvent(e)).toBe(true);
    expect(await s.insertEvent(e)).toBe(false);
    expect(await s.insertEvent({ ...e, logIndex: 1 })).toBe(true);
  });
});

describe("API", () => {
  it("health works", async () => {
    const { app } = mk();
    expect((await request(app).get("/health")).body).toEqual({ ok: true, db: true });
  });
  it("validates input", async () => {
    const { app } = mk();
    expect((await request(app).get("/api/guards?owner=nope")).status).toBe(400);
    expect((await request(app).post("/api/transactions").send({ chainId: 1, txHash: "0x1", label: "x" })).status).toBe(400);
  });
  it("records a tx as pending and lists it", async () => {
    const { app } = mk();
    expect((await request(app).post("/api/transactions").send({ chainId: 84532, txHash: H, guard: G, label: "approve" })).status).toBe(202);
    const r = await request(app).get(`/api/transactions?guard=${G}`);
    expect(r.body.transactions[0]).toMatchObject({ status: "pending", label: "approve" });
  });
  it("summarizes indexed events", async () => {
    const { app, store } = mk();
    await store.insertEvent({ chainId: 84532, txHash: H, logIndex: 0, blockNumber: 5, kind: "revoked", guard: G });
    const r = await request(app).get(`/api/summary?guard=${G}`);
    expect(r.body.counts.revocations).toBe(1);
  });
  it("sync is unavailable when not configured", async () => {
    const { app } = mk();
    expect((await request(app).post("/api/sync")).status).toBe(503);
  });
});

import { syncAll } from "../src/indexer.js";
import { guardAbi as gAbi } from "../src/abi.js";

describe("indexer", () => {
  it("rewinds guard cursors when a new guard is discovered, and is idempotent", async () => {
    const store = new MemoryStore();
    await store.setCursor("base:guards", 100);
    await store.setCursor("base:token", 100);
    const F = "0x4444444444444444444444444444444444444444";
    const created = {
      address: F, blockNumber: 50n, transactionHash: H, logIndex: 0,
      topics: encodeEventTopics({ abi: factoryAbi, eventName: "GuardCreated", args: { owner: A, guard: G } }),
      data: encodeAbiParameters([{ type: "bool" }, { type: "bool" }, { type: "uint256" }], [true, true, 0n]),
    };
    const client = {
      getBlockNumber: async () => 100n,
      getBlock: async () => ({ timestamp: 1n }),
      getLogs: async ({ address }: any) => (address === F ? [created] : []),
      getTransactionReceipt: async () => { throw new Error("none"); },
    };
    const cfg: any = { GUARD_FACTORY: F };
    const r1 = await syncAll(store, cfg, { base: client, lasna: client });
    expect(r1.inserted).toBe(1);
    expect(await store.getCursor("base:guards")).toBe(100); // rewound to 49 then rescanned to head
    expect((await store.allGuards()).length).toBe(1);
    const r2 = await syncAll(store, cfg, { base: client, lasna: client });
    expect(r2.inserted).toBe(0);
    void gAbi;
  });
});
