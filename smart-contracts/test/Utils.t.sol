// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { IUniswapV2Factory } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import { Utils } from "script/Utils.sol";

contract UtilsTest is Test {
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig config;
    // https://github.com/sushi-labs/sushiswap/blob/75219a75bfdb4ec8fa2d998b6535b0fd14017acc/packages/v2-sdk/src/constants.ts#L194
    bytes public constant UNISWAP_V2_INIT_CODE = hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f";
    // https://github.com/sushi-labs/sushiswap/issues/115
    bytes public constant SUSHISWAP_V2_INIT_CODE = hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303";

    function setUp() public {
        helperConfig = new HelperConfig();
        config = helperConfig.getActiveNetworkConfig();
    }

    function test_getPairs() public view {
        IUniswapV2Factory factoryOne = IUniswapV2Factory(config.dexFactories[0]);
        IUniswapV2Pair pairOne = IUniswapV2Pair(factoryOne.getPair(config.tokenToBorrow, config.tokenToSwap));

        (address token0, address token1) = Utils.sortTokens(config.tokenToBorrow, config.tokenToSwap);
        assertEq(
            address(pairOne), Utils.calculatePairAddress(config.dexFactories[0], token0, token1, UNISWAP_V2_INIT_CODE)
        );

        IUniswapV2Factory factoryTwo = IUniswapV2Factory(config.dexFactories[1]);
        IUniswapV2Pair pairTwo = IUniswapV2Pair(factoryTwo.getPair(config.tokenToBorrow, config.tokenToSwap));
        assertEq(
            address(pairTwo), Utils.calculatePairAddress(config.dexFactories[1], token0, token1, SUSHISWAP_V2_INIT_CODE)
        );
    }
}
