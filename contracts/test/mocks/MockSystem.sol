// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";

/// @dev Local stand-in for the Lasna system contract (etched at 0x8888...8888 in tests).
contract MockSystem {
    struct Sub {
        uint256 chainId;
        address c;
        uint256 t0;
    }
    Sub[] public subs;
    ISystemContract.CallbackConfiguration_V_1_0 public lastCallback;
    uint256 public callbackCount;

    receive() external payable {}

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    function subscribe(uint256 chainId, address c, uint256 t0, uint256, uint256, uint256) external {
        subs.push(Sub(chainId, c, t0));
    }

    function subsLength() external view returns (uint256) {
        return subs.length;
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory cfg) external {
        lastCallback = cfg;
        callbackCount++;
    }

    function lastPayload() external view returns (bytes memory) {
        return lastCallback.payload;
    }
}
