// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {ChainGuardReactive} from "../src/reactive/ChainGuardReactive.sol";

/// Step 1 (Lasna): deploy the reactive contract, watching the demo token on Base Sepolia.
/// Requires MOCK_ERC20 (deployed first on Base Sepolia) - token address is known before the factory.
contract DeployLasna is Script {
    uint256 constant ORIGIN_CHAIN_ID = 84532; // Base Sepolia (fixed: not configurable)
    uint256 constant MAX_GUARDS = 50; // bounds runtime-subscription work an open factory can force on the reactive contract

    function run() external {
        require(block.chainid == 5318007, "ChainGuard: Reactive Lasna (5318007) only");
        address token = vm.envAddress("MOCK_ERC20");
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        vm.startBroadcast();
        ChainGuardReactive rc = new ChainGuardReactive(ORIGIN_CHAIN_ID, tokens, MAX_GUARDS);
        vm.stopBroadcast();
        console.log("ChainGuardReactive:", address(rc));
    }
}
