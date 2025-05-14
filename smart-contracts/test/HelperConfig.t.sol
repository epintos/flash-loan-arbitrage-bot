// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { IUniswapV2Factory } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import { Utils } from "script/Utils.s.sol";

contract HelperConfigTest is Test {
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig config;

    function setUp() public {
        helperConfig = new HelperConfig();
        config = helperConfig.getActiveNetworkConfig();
    }

    function test_getPairs() public view {
        IUniswapV2Factory factoryOne = IUniswapV2Factory(config.dexFactories[0]);
        IUniswapV2Pair pairOne = IUniswapV2Pair(factoryOne.getPair(config.tokenToBorrow, config.tokenToSwap));
        assertEq(address(pairOne), config.dexPairs[0]);

        IUniswapV2Factory factoryTwo = IUniswapV2Factory(config.dexFactories[1]);
        IUniswapV2Pair pairTwo = IUniswapV2Pair(factoryTwo.getPair(config.tokenToBorrow, config.tokenToSwap));
        assertEq(address(pairTwo), config.dexPairs[1]);
    }
}
