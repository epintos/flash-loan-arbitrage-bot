// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { Test, console } from "forge-std/Test.sol";
import { FlashLoanArbitrage } from "src/FlashLoanArbitrage.sol";
import { Deploy } from "script/Deploy.s.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IUniswapV2Factory } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

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

    // checkArbitrageProfitability
    function test_checkArbitrageProfitability_Negative(uint256 amount) external {
        amount = bound(amount, 0.01 ether, MAX_TO_BORROW);

        vm.prank(OWNER);
        int256 profitability = arbitrageContract.checkArbitrageProfitability(tokenToBorrow, tokenToSwap, amount);
        assertLt(profitability, 0);
    }

    // Withdraw
    function test_withdraw() public {
        deal(tokenToBorrow, address(arbitrageContract), MAX_TO_BORROW);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", address(this)));
        arbitrageContract.withdraw(tokenToBorrow, 1 ether);

        vm.prank(OWNER);
        arbitrageContract.withdraw(tokenToBorrow, 1 ether);
        assertEq(IERC20(tokenToBorrow).balanceOf(OWNER), 1 ether);

        vm.prank(OWNER);
        arbitrageContract.withdraw(tokenToBorrow, type(uint256).max);
        assertEq(IERC20(tokenToBorrow).balanceOf(OWNER), MAX_TO_BORROW);
        assertEq(IERC20(tokenToBorrow).balanceOf(address(arbitrageContract)), 0);
    }

    // updateSwapTimeout
    function test_updateSwapTimeout() public {
        uint256 newTime = 2 minutes;
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", address(this)));
        arbitrageContract.updateSwapTimeout(newTime);

        vm.prank(OWNER);
        arbitrageContract.updateSwapTimeout(newTime);
        assertEq(arbitrageContract.SWAP_TIMEOUT(), newTime);
    }

    // updateDEXes
    function test_updateDEXes() public {
        address[] memory newDexRouters = new address[](2);
        newDexRouters[0] = makeAddr("Router1");
        newDexRouters[1] = makeAddr("Router2");
        address[] memory newDexFactories = new address[](2);
        newDexFactories[0] = makeAddr("Factory1");
        newDexFactories[1] = makeAddr("Factory2");

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", address(this)));
        arbitrageContract.updateDEXes(newDexRouters, newDexFactories);

        address[] memory newDexFactoriesInvalid = new address[](1);
        newDexFactoriesInvalid[0] = makeAddr("Factory1");

        vm.prank(OWNER);
        vm.expectRevert(FlashLoanArbitrage.FlashLoanArbitrage__InvalidAmountOfRoutersAndFactories.selector);
        arbitrageContract.updateDEXes(newDexRouters, newDexFactoriesInvalid);

        vm.prank(OWNER);
        arbitrageContract.updateDEXes(newDexRouters, newDexFactories);
        assertEq(arbitrageContract.dexRouters(0), newDexRouters[0]);
        assertEq(arbitrageContract.dexRouters(1), newDexRouters[1]);
        assertEq(arbitrageContract.dexFactories(0), newDexFactories[0]);
        assertEq(arbitrageContract.dexFactories(1), newDexFactories[1]);
    }
}
