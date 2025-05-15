// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { FlashLoanArbitrage } from "src/FlashLoanArbitrage.sol";
import { IUniswapV2Pair } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Factory } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import { Utils } from "script/Utils.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { Utils } from "script/Utils.sol";
import { IERC20 } from "@balancer-labs/v2-interfaces/solidity-utils/openzeppelin/IERC20.sol";

contract ChangeReserves is Script {
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig config;

    address constant WETH_WHALE_ACCOUNT = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
    address constant LINK_WHALE_ACCOUNT = 0x5a52E96BAcdaBb82fd05763E25335261B270Efcb;
    mapping(address token => address whale) whales;

    function run() public {
        helperConfig = new HelperConfig();
        config = helperConfig.getActiveNetworkConfig();

        (address token0, address token1) = Utils.sortTokens(config.tokenToBorrow, config.tokenToSwap);
        if (token0 == config.tokenToBorrow) {
            whales[token0] = WETH_WHALE_ACCOUNT;
            whales[token1] = LINK_WHALE_ACCOUNT;
        } else {
            whales[token0] = LINK_WHALE_ACCOUNT;
            whales[token1] = WETH_WHALE_ACCOUNT;
        }
        address pairUni = IUniswapV2Factory(config.dexFactories[0]).getPair(config.tokenToBorrow, config.tokenToSwap);
        address pairSushi = IUniswapV2Factory(config.dexFactories[1]).getPair(config.tokenToBorrow, config.tokenToSwap);

        vm.startBroadcast(msg.sender);
        // Uniswap: cheaper
        if (token0 == config.tokenToBorrow) {
            IERC20(token0).transfer(pairUni, 5 ether);
            IERC20(token1).transfer(pairUni, 10_000 ether);
        } else {
            IERC20(token0).transfer(pairUni, 10_000 ether);
            IERC20(token1).transfer(pairUni, 5 ether);
        }

        // Sushi: more expensive
        if (token0 == config.tokenToBorrow) {
            IERC20(token0).transfer(pairSushi, 20 ether);
            IERC20(token1).transfer(pairSushi, 10_000 ether);
        } else {
            IERC20(token0).transfer(pairSushi, 80 ether);
            IERC20(token1).transfer(pairSushi, 10_000 ether);
        }

        // Trigger sync so reserves are updated
        IUniswapV2Pair(pairUni).sync();
        IUniswapV2Pair(pairSushi).sync();
        vm.stopBroadcast();
    }
}
