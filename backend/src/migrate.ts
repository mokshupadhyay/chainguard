import { readFileSync, readdirSync } from "node:fs";
import pg from "pg";
import "dotenv/config";

const url = process.env.DATABASE_URL;
if (!url) throw new Error("DATABASE_URL required");
const pool = new pg.Pool({ connectionString: url, ssl: { rejectUnauthorized: false } });
for (const f of readdirSync("migrations").sort()) {
  await pool.query(readFileSync(`migrations/${f}`, "utf8"));
  console.log("applied", f);
}
await pool.end();
