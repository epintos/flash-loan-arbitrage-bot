// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { Test, console } from "forge-std/Test.sol";
import { FlashLoanArbitrage } from "src/FlashLoanArbitrage.sol";
import { Deploy } from "script/Deploy.s.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IUniswapV2Factory } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

// contract FlashLoanArbitragePublic is FlashLoanArbitrage {
//     constructor(
//         address _balancerVault,
//         address[] memory _dexRouters,
//         address[] memory _dexFactories
//     )
//         FlashLoanArbitrage(_balancerVault, _dexRouters, _dexFactories)
//     { }

//     function getDEXPricePublic(
//         uint256 dexIndex,
//         address tokenIn,
//         address tokenOut,
//         uint256 amountIn
//     )
//         internal
//         view
//         returns (uint256 amountOut)
//     {
//         return super.getDEXPrice(dexIndex, tokenIn, tokenOut, amountIn);
//     }
// }

contract FlashLoanArbitrageTest is Test {
    FlashLoanArbitrage arbitrageContract;
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig config;
    address OWNER = makeAddr("OWNER");
    uint256 constant MAX_TO_BORROW = 1 ether;
    address tokenToBorrow;
    address tokenToSwap;

    function setUp() public {
        (arbitrageContract, helperConfig) = new Deploy().run();
        config = helperConfig.getActiveNetworkConfig();

        arbitrageContract.transferOwnership(OWNER);

        tokenToBorrow = config.tokenToBorrow;
        tokenToSwap = config.tokenToSwap;
    }

    // Helper fuction
    function _sortTokens(address tokenA, address tokenB) private pure returns (address token0, address token1) {
        require(tokenA != tokenB, "Identical addresses");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    // executeArbitrage
    function test_executeArbitrage(uint256 amount) external {
        amount = bound(amount, 0.01 ether, MAX_TO_BORROW);

        // Modify reserves to be able to test a profiteable arbitrage
        (address token0, address token1) = _sortTokens(tokenToBorrow, tokenToSwap);

        address pairUni = IUniswapV2Factory(config.dexFactories[0]).getPair(tokenToBorrow, tokenToSwap);
        address pairSushi = IUniswapV2Factory(config.dexFactories[1]).getPair(tokenToBorrow, tokenToSwap);

        // Uniswap: cheaper
        if (token0 == tokenToBorrow) {
            deal(token0, pairUni, 5 ether); // tokenToBorrow
            deal(token1, pairUni, 10_000 ether); // tokenToSwap
        } else {
            deal(token0, pairUni, 10_000 ether); // tokenToSwap
            deal(token1, pairUni, 5 ether); // tokenToBorrow
        }
        IUniswapV2Pair(pairUni).sync();

        // Sushi: more expensive
        if (token0 == tokenToBorrow) {
            deal(token0, pairSushi, 20 ether); // tokenToBorrow
            deal(token1, pairSushi, 10_000 ether); // tokenToSwap
        } else {
            deal(token0, pairSushi, 10_000 ether); // tokenToSwap
            deal(token1, pairSushi, 20 ether); // tokenToBorrow
        }

        // Trigger sync so reserves are updated
        IUniswapV2Pair(pairUni).sync();
        IUniswapV2Pair(pairSushi).sync();

        vm.prank(OWNER);
        int256 profitability = arbitrageContract.checkArbitrageProfitability(tokenToBorrow, tokenToSwap, amount);
        assertGt(profitability, 0);

        uint256 initialBalance = IERC20(tokenToBorrow).balanceOf(address(arbitrageContract));

        vm.prank(OWNER);
        arbitrageContract.executeArbitrage(tokenToBorrow, amount, tokenToSwap);
        uint256 finalBalance = IERC20(tokenToBorrow).balanceOf(address(arbitrageContract));
        assertGt(finalBalance, initialBalance);
    }
}
