// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { FlashLoanArbitrage } from "src/FlashLoanArbitrage.sol";

contract HelperConfig is Script {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        // https://docs-v2.balancer.fi/reference/contracts/deployment-addresses/mainnet.html
        // UniSwap v2: https://docs.uniswap.org/contracts/v2/reference/smart-contracts/v2-deployments
        // SushiSwap v2: https://docs.sushi.com/contracts/cpamm
        address balancerVault;
        address[2] dexRouters;
        address[2] dexFactories;
        // WETH
        address tokenToBorrow;
        // LINK: https://docs.chain.link/resources/link-token-contracts#ethereum-mainnet
        address tokenToSwap;
    }

    uint256 public constant MAINNET_CHAIN_ID = 1;

    NetworkConfig private activeNetworkConfig;

    constructor() {
        if (block.chainid == MAINNET_CHAIN_ID) {
            activeNetworkConfig = getMainnetETHConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }

    function getMainnetETHConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            balancerVault: 0xBA12222222228d8Ba445958a75a0704d566BF2C8,
            dexRouters: [0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F],
            dexFactories: [0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f, 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac],
            tokenToBorrow: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            tokenToSwap: 0x514910771AF9Ca656af840dff83E8264EcF986CA
        });
    }
}
