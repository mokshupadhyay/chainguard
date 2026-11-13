// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {AbstractCallback} from "@reactive/src/base/AbstractCallback.sol";

interface IERC20Min {
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title GuardModule
/// @notice A user-owned vault that holds tokens and is itself the ERC-20 `owner` of every
/// approval it creates. Because the Guard is the approver, it can legitimately revoke
/// (`approve(spender, 0)`) when the ChainGuardReactive contract on Reactive Lasna asks it to.
/// The Guard never decides policy on-chain-callback side: it only publishes the policy
/// (via `ChainGuardPolicySet`) and executes revocations requested by its trusted reactive sender.
contract GuardModule is AbstractCallback {
    address public immutable owner;

    struct Policy {
        bool enabled;
        bool revokeUnlimited;
        uint256 maxAllowance; // 0 = cap disabled
    }

    Policy public policy;

    /// @notice True once Reactive Lasna has confirmed (by callback) that this Guard is registered
    /// and its scoped subscriptions were requested. Until then approvals/policy changes are blocked.
    bool public ready;
    /// @notice Tokens Reactive Lasna confirmed it watches for this Guard. Other tokens are unsupported.
    mapping(address => bool) public protectedToken;
    /// @notice Spender allowlist (enforced on Lasna, not here: the owner can still approve anyone and
    /// ChainGuard cleans up). Only meaningful when `restrictSpenders` is true.
    bool public restrictSpenders;
    mapping(address => bool) public allowedSpender;

    /// @dev Reactive Lasna subscribes to this event and mirrors the policy into `react()` state.
    event ChainGuardPolicySet(
        address indexed owner, bool enabled, bool revokeUnlimited, uint256 maxAllowance
    );
    /// @dev Spender-allowlist rules, mirrored into `react()` on Lasna (separate events keep the
    /// ChainGuardPolicySet ABI unchanged).
    event SpenderModeSet(bool restrictToAllowlist);
    event SpenderRuleSet(address indexed spender, bool allowed);
    event Revoked(address indexed token, address indexed spender, uint256 previousAllowance);
    /// @dev A callback arrived but the allowance had already changed (e.g. the owner corrected an
    /// unlimited approval to a small one), so the newer approval is left alone.
    event RevokeSkipped(
        address indexed token, address indexed spender, uint256 expected, uint256 current
    );
    event Approved(address indexed token, address indexed spender, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    event ProtectionConfirmed(address indexed reactiveSender, address[] tokens);

    error NotOwner();
    error NotProtected(); // Lasna has not confirmed registration yet
    error UnsupportedToken(address token); // token is not on the protected allowlist

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyReady() {
        if (!ready) revert NotProtected();
        _;
    }

    constructor(
        address owner_,
        IPayable callbackProxy_,
        address reactive_,
        Policy memory initialPolicy_
    ) payable AbstractCallback(callbackProxy_, reactive_) {
        owner = owner_;
        policy = initialPolicy_;
        emit ChainGuardPolicySet(
            owner_,
            initialPolicy_.enabled,
            initialPolicy_.revokeUnlimited,
            initialPolicy_.maxAllowance
        );
    }

    // ---------------------------------------------------------------- owner actions

    function setPolicy(bool enabled, bool revokeUnlimited, uint256 maxAllowance)
        external
        onlyOwner
        onlyReady
    {
        policy = Policy(enabled, revokeUnlimited, maxAllowance);
        emit ChainGuardPolicySet(owner, enabled, revokeUnlimited, maxAllowance);
    }

    /// @notice When on, Lasna revokes ANY approval to a spender not on the allowlist (even a small one).
    function setSpenderMode(bool restrictToAllowlist) external onlyOwner onlyReady {
        restrictSpenders = restrictToAllowlist;
        emit SpenderModeSet(restrictToAllowlist);
    }

    function setSpenderAllowed(address spender, bool allowed) external onlyOwner onlyReady {
        allowedSpender[spender] = allowed;
        emit SpenderRuleSet(spender, allowed);
    }

    /// @notice Guard (not the EOA) grants the allowance, so the Guard is the approval owner.
    /// Blocked until Lasna confirms registration, and only for tokens Lasna actually watches:
    /// an approval on an unwatched token could never be revoked automatically.
    function approveToken(address token, address spender, uint256 amount)
        external
        onlyOwner
        onlyReady
    {
        if (!protectedToken[token]) revert UnsupportedToken(token);
        IERC20Min(token).approve(spender, amount);
        emit Approved(token, spender, amount);
    }

    /// @notice Manual revoke by the owner.
    function revokeManually(address token, address spender) external onlyOwner {
        _revoke(token, spender);
    }

    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        require(IERC20Min(token).transfer(to, amount), "transfer failed");
        emit Withdrawn(token, to, amount);
    }

    function withdrawNative(address payable to, uint256 amount) external onlyOwner {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "native transfer failed");
    }

    /// @notice Anyone may settle callback-proxy debt from this contract's native balance.
    function coverDebt() external {
        _coverDebt();
    }

    // ---------------------------------------------------------------- reactive callback

    /// @param reactiveSender First argument is overwritten by the callback proxy with the
    /// requesting reactive contract's address; we require it to be our trusted reactive sender.
    function revoke(address reactiveSender, address token, address spender)
        external
        onlyServiceProvider
        onlyCallbackSender(reactiveSender)
    {
        _revoke(token, spender);
    }

    /// @notice Approval-triggered revoke: only acts if the allowance still equals the value Lasna
    /// evaluated, so a late callback can never zero a newer, safe approval.
    function revokeIfUnchanged(
        address reactiveSender,
        address token,
        address spender,
        uint256 expected
    ) external onlyServiceProvider onlyCallbackSender(reactiveSender) {
        uint256 current = IERC20Min(token).allowance(address(this), spender);
        if (current != expected) {
            emit RevokeSkipped(token, spender, expected, current);
            return;
        }
        _revoke(token, spender);
    }

    /// @notice Registration confirmation sent by ChainGuardReactive right after it registers this Guard
    /// and requests the Guard-scoped subscriptions. Same trust checks as `revoke`.
    function confirmRegistered(address reactiveSender, address[] calldata tokens)
        external
        onlyServiceProvider
        onlyCallbackSender(reactiveSender)
    {
        for (uint256 i; i < tokens.length; i++) {
            protectedToken[tokens[i]] = true;
        }
        ready = true;
        emit ProtectionConfirmed(reactiveSender, tokens);
    }

    function _revoke(address token, address spender) internal {
        uint256 prev = IERC20Min(token).allowance(address(this), spender);
        if (prev == 0) return; // idempotent: nothing to revoke
        IERC20Min(token).approve(spender, 0);
        emit Revoked(token, spender, prev);
    }
}
