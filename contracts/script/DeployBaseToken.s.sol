// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// Step 0 (Base Sepolia): deploy the demo token.
contract DeployBaseToken is Script {
    function run() external {
        require(block.chainid == 84532, "ChainGuard: Base Sepolia (84532) only");
        vm.startBroadcast();
        MockERC20 t = new MockERC20("ChainGuard Mock USDC", "cgUSDC");
        vm.stopBroadcast();
        console.log("MockERC20:", address(t));
    }
}
