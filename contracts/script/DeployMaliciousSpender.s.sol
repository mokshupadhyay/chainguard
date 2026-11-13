// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {MaliciousSpender} from "../src/MaliciousSpender.sol";

/// Demo only (Base Sepolia): deploy the attacker contract used to show a drain with protection off vs on.
contract DeployMaliciousSpender is Script {
    function run() external {
        require(block.chainid == 84532, "ChainGuard: Base Sepolia (84532) only");
        vm.startBroadcast();
        MaliciousSpender m = new MaliciousSpender();
        vm.stopBroadcast();
        console.log("MaliciousSpender:", address(m));
    }
}
