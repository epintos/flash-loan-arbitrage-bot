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
        address[2] dexPairs;
        address[2] dexFactories;
        // WETH
        address tokenToBorrow;
        // LINK: https://docs.chain.link/resources/link-token-contracts#ethereum-mainnet
        address tokenToSwap;
    }

    uint256 public constant MAINNET_CHAIN_ID = 1;

    // UniSwap: https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/getting-pair-addresses
    // SushiSwap:
    // https://github.com/sushi-labs/sushiswap/blob/75219a75bfdb4ec8fa2d998b6535b0fd14017acc/packages/v2-sdk/src/constants.ts#L194
    bytes public constant UNISWAP_V2_INIT_CODE = hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f";
    // https://github.com/sushi-labs/sushiswap/issues/115
    bytes public constant SUSHISWAP_V2_INIT_CODE = hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303";
    address public constant TOKEN_TO_BORROW = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant TOKEN_TO_SWAP = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address public constant DEX_1_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant DEX_2_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

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
        (address token0, address token1) = Utils.sortTokens(TOKEN_TO_BORROW, TOKEN_TO_SWAP);

        address pairOne = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", DEX_1_FACTORY, keccak256(abi.encodePacked(token0, token1)), UNISWAP_V2_INIT_CODE
                        )
                    )
                )
            )
        );

        address pairTwo = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", DEX_2_FACTORY, keccak256(abi.encodePacked(token0, token1)), SUSHISWAP_V2_INIT_CODE
                        )
                    )
                )
            )
        );

        return NetworkConfig({
            balancerVault: 0xBA12222222228d8Ba445958a75a0704d566BF2C8,
            dexRouters: [0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F],
            dexPairs: [pairOne, pairTwo],
            dexFactories: [DEX_1_FACTORY, DEX_2_FACTORY],
            tokenToBorrow: TOKEN_TO_BORROW,
            tokenToSwap: TOKEN_TO_SWAP
        });
    }
}
