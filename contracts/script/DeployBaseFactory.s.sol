// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {GuardFactory} from "../src/GuardFactory.sol";

/// Step 2 (Base Sepolia): deploy the factory pointing at the Lasna reactive contract.
contract DeployBaseFactory is Script {
    // Callback proxy for Base Sepolia, per https://dev.reactive.network/origins-and-destinations
    address constant CALLBACK_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;

    function run() external {
        require(block.chainid == 84532, "ChainGuard: Base Sepolia (84532) only");
        address reactive = vm.envAddress("CHAINGUARD_REACTIVE");
        vm.startBroadcast();
        GuardFactory f = new GuardFactory(IPayable(payable(CALLBACK_PROXY)), reactive);
        vm.stopBroadcast();
        console.log("GuardFactory:", address(f));
    }
}
