import { parseAbi } from 'viem'

export const factoryAbi = parseAbi([
  'function createGuard() payable returns (address)',
  'function guardsOf(address owner) view returns (address[])',
])
export const guardAbi = parseAbi([
  'function owner() view returns (address)',
  'function policy() view returns (bool enabled, bool revokeUnlimited, uint256 maxAllowance)',
  'function setPolicy(bool enabled, bool revokeUnlimited, uint256 maxAllowance)',
  'function approveToken(address token, address spender, uint256 amount)',
  'function revokeManually(address token, address spender)',
  'function withdraw(address token, address to, uint256 amount)',
  'event Revoked(address indexed token, address indexed spender, uint256 previousAllowance)',
  'event Approved(address indexed token, address indexed spender, uint256 amount)',
])
export const erc20Abi = parseAbi([
  'function balanceOf(address) view returns (uint256)',
  'function allowance(address owner, address spender) view returns (uint256)',
  'function mint(address to, uint256 amount)',
  'function symbol() view returns (string)',
])
export const reactiveAbi = parseAbi([
  'function policies(address guard) view returns (bool enabled, bool revokeUnlimited, uint256 maxAllowance)',
  'event RevokeRequested(address indexed guard, address indexed token, address indexed spender, uint256 value, string reason)',
])
