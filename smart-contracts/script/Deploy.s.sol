// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { FlashLoanArbitrage } from "src/FlashLoanArbitrage.sol";
import { HelperConfig } from "./HelperConfig.s.sol";

contract Deploy is Script {
    function run() external returns (FlashLoanArbitrage, HelperConfig) {
        vm.startBroadcast(msg.sender);
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();
        address balanceVault = config.balancerVault;

        address[] memory dexRouters = new address[](2);
        address[] memory dexPairs = new address[](2);

        for (uint256 i = 0; i < 2; i++) {
            dexRouters[i] = config.dexRouters[i];
            dexPairs[i] = config.dexPairs[i];
        }

        FlashLoanArbitrage arbitrageContract = new FlashLoanArbitrage(balanceVault, dexRouters, dexPairs);
        vm.stopBroadcast();

        return (arbitrageContract, helperConfig);
    }
}
