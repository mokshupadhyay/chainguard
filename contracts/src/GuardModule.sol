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

    /// @dev Reactive Lasna subscribes to this event and mirrors the policy into `react()` state.
    event ChainGuardPolicySet(
        address indexed owner, bool enabled, bool revokeUnlimited, uint256 maxAllowance
    );
    event Revoked(address indexed token, address indexed spender, uint256 previousAllowance);
    event Approved(address indexed token, address indexed spender, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
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
    {
        policy = Policy(enabled, revokeUnlimited, maxAllowance);
        emit ChainGuardPolicySet(owner, enabled, revokeUnlimited, maxAllowance);
    }

    /// @notice Guard (not the EOA) grants the allowance, so the Guard is the approval owner.
    function approveToken(address token, address spender, uint256 amount) external onlyOwner {
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

    function _revoke(address token, address spender) internal {
        uint256 prev = IERC20Min(token).allowance(address(this), spender);
        if (prev == 0) return; // idempotent: nothing to revoke
        IERC20Min(token).approve(spender, 0);
        emit Revoked(token, spender, prev);
    }
}
