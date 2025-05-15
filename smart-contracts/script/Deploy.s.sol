// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { FlashLoanArbitrage } from "src/FlashLoanArbitrage.sol";
import { HelperConfig } from "./HelperConfig.s.sol";

contract Deploy is Script {
    function run() external returns (FlashLoanArbitrage, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        address balanceVault = config.balancerVault;

        address[] memory dexRouters = new address[](2);
        address[] memory dexFactories = new address[](2);

        for (uint256 i = 0; i < 2; i++) {
            dexRouters[i] = config.dexRouters[i];
            dexFactories[i] = config.dexFactories[i];
        }

        vm.startBroadcast(msg.sender);

        FlashLoanArbitrage arbitrageContract = new FlashLoanArbitrage(balanceVault, dexRouters, dexFactories);

        vm.stopBroadcast();

        return (arbitrageContract, helperConfig);
    }
}
