// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { FlashLoanArbitrage } from "src/FlashLoanArbitrage.sol";
import { Utils } from "script/Utils.s.sol";

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
    uint256 public constant SEPOLIA_CHAIN_ID = 11_155_111;

    NetworkConfig private activeNetworkConfig;

    constructor() {
        if (block.chainid == MAINNET_CHAIN_ID) {
            activeNetworkConfig = getMainnetETHConfig();
        } else if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaETHConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }

    function getSepoliaETHConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            balancerVault: 0xBA12222222228d8Ba445958a75a0704d566BF2C8,
            dexRouters: [0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3, 0xeaBcE3E74EF41FB40024a21Cc2ee2F5dDc615791],
            dexFactories: [0xF62c03E08ada871A0bEb309762E260a7a6a880E6, 0x734583f62Bb6ACe3c9bA9bd5A53143CA2Ce8C55A],
            tokenToBorrow: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            tokenToSwap: 0x779877A7B0D9E8603169DdbD7836e478b4624789
        });
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
