import { parseAbi } from "viem";

export const factoryAbi = parseAbi(["event GuardCreated(address indexed owner, address indexed guard)"]);
export const guardAbi = parseAbi([
  "event ChainGuardPolicySet(address indexed owner, bool enabled, bool revokeUnlimited, uint256 maxAllowance)",
  "event Revoked(address indexed token, address indexed spender, uint256 previousAllowance)",
  "event Approved(address indexed token, address indexed spender, uint256 amount)",
]);
export const erc20ApprovalAbi = parseAbi(["event Approval(address indexed owner, address indexed spender, uint256 value)"]);
export const reactiveAbi = parseAbi([
  "event PolicyMirrored(address indexed guard, bool enabled, bool revokeUnlimited, uint256 maxAllowance)",
  "event RevokeRequested(address indexed guard, address indexed token, address indexed spender, uint256 value, string reason)",
  "event ApprovalIgnored(address indexed guard, address indexed token, address indexed spender, uint256 value)",
]);
