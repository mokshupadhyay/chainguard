// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {GuardModule} from "./GuardModule.sol";

/// @title GuardFactory
/// @notice One-click Guard deployment for `msg.sender`, pre-wired to the trusted reactive contract.
contract GuardFactory {
    IPayable public immutable callbackProxy;
    address public immutable reactive;

    mapping(address => address[]) private _guardsOf;

    /// @dev Carries the initial policy: the Guard emits it in its constructor, before Lasna can subscribe to it.
    event GuardCreated(
        address indexed owner,
        address indexed guard,
        bool enabled,
        bool revokeUnlimited,
        uint256 maxAllowance
    );

    constructor(IPayable callbackProxy_, address reactive_) {
        callbackProxy = callbackProxy_;
        reactive = reactive_;
    }

    /// @notice Deploys a Guard owned by msg.sender. Any ETH sent funds callback gas for the Guard.
    /// Default policy: enabled, revoke unlimited approvals, no cap.
    function createGuard() external payable returns (address guard) {
        GuardModule.Policy memory p = GuardModule.Policy(true, true, 0);
        guard = address(new GuardModule{value: msg.value}(msg.sender, callbackProxy, reactive, p));
        _guardsOf[msg.sender].push(guard);
        emit GuardCreated(msg.sender, guard, p.enabled, p.revokeUnlimited, p.maxAllowance);
    }

    function guardsOf(address owner) external view returns (address[] memory) {
        return _guardsOf[owner];
    }
}
