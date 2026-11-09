import type { Log } from "viem";
import { decodeEventLog } from "viem";
import { erc20ApprovalAbi, factoryAbi, guardAbi, reactiveAbi } from "./abi.js";
import type { EventRow } from "./types.js";

const abis = [factoryAbi, guardAbi, erc20ApprovalAbi, reactiveAbi].flat();

/** Pure: turn a raw chain log into an idempotent EventRow (or null if not a ChainGuard event). */
export function decodeLog(chainId: number, log: Pick<Log, "topics" | "data" | "transactionHash" | "logIndex" | "blockNumber" | "address">, blockTime?: string | null): EventRow | null {
  if (log.transactionHash == null || log.logIndex == null || log.blockNumber == null) return null;
  let d: { eventName: string; args: any };
  try {
    d = decodeEventLog({ abi: abis, topics: log.topics as any, data: log.data }) as any;
  } catch {
    return null;
  }
  const base = { chainId, txHash: log.transactionHash, logIndex: Number(log.logIndex), blockNumber: Number(log.blockNumber), blockTime };
  const a = d.args;
  switch (d.eventName) {
    case "GuardCreated":
      return { ...base, kind: "guard_created", guard: a.guard, data: { owner: a.owner, enabled: a.enabled, revokeUnlimited: a.revokeUnlimited, maxAllowance: a.maxAllowance.toString() } };
    case "ChainGuardPolicySet":
      return { ...base, kind: "policy_set", guard: log.address, data: { enabled: a.enabled, revokeUnlimited: a.revokeUnlimited, maxAllowance: a.maxAllowance.toString() } };
    case "Revoked":
      return { ...base, kind: "revoked", guard: log.address, token: a.token, spender: a.spender, value: a.previousAllowance.toString() };
    case "Approved":
      return { ...base, kind: "approved", guard: log.address, token: a.token, spender: a.spender, value: a.amount.toString() };
    case "Approval":
      return { ...base, kind: "approval_observed", guard: a.owner, token: log.address, spender: a.spender, value: a.value.toString() };
    case "GuardRegistered":
      return { ...base, kind: "guard_registered", guard: a.guard, data: { owner: a.owner, enabled: a.enabled, revokeUnlimited: a.revokeUnlimited, maxAllowance: a.maxAllowance.toString() } };
    case "PolicyMirrored":
      return { ...base, kind: "policy_mirrored", guard: a.guard, data: { enabled: a.enabled, revokeUnlimited: a.revokeUnlimited, maxAllowance: a.maxAllowance.toString() } };
    case "RevokeRequested":
      return { ...base, kind: "revoke_requested", guard: a.guard, token: a.token, spender: a.spender, value: a.value.toString(), data: { reason: a.reason } };
    case "ApprovalIgnored":
      return { ...base, kind: "approval_ignored", guard: a.guard, token: a.token, spender: a.spender, value: a.value.toString() };
    default:
      return null;
  }
}
