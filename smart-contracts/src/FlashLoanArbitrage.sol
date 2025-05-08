// SDPX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IVault } from "@balancer-labs/v2-interfaces/vault/IVault.sol";
import { IFlashLoanRecipient } from "@balancer-labs/v2-interfaces/vault/IFlashLoanRecipient.sol";
import { IERC20 } from "@balancer-labs/v2-interfaces/solidity-utils/openzeppelin/IERC20.sol";
import { IUniswapV2Router02 } from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Factory } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract FlashLoanArbitrage is IFlashLoanRecipient, Ownable {
    error FlashLoanArbitrage__NotBalancerVault();
    error FlashLoanArbitrage__NotEnoughToRepayFlashLoan();
    error FlashLoanArbitrage__InvalidAmountOfRoutersAndFactories();

    // Address of the Balancer Vault for flash loans
    address private balancerVault;

    // Router addresses for different Uniswap V2 Fork DEXes
    address[] private dexRouters;

    // Factory addresses for different Uniswap V2 Fork DEXes
    address[] private dexFactories;

    constructor(address _balancerVault, address _dexRouters, address _dexFactories) Ownable(msg.sender) {
        balancerVault = _balancerVault;
        if (_dexRouters.length != _dexFactories.length && _dexRouters.length != 2) {
            revert FlashLoanArbitrage__InvalidAmountOfRoutersAndFactories();
        }
        dexRouters = _dexRouters;
        dexFactories = _dexFactories;
    }

    /**
     * @notice Function to execute flash loan and perform arbitrage
     * @param tokenToBorrow Address of the token to borrow in the flash loan
     * @param amount Amount of tokens to borrow
     * @param tokenToSwap Address of the token to swap for
     */
    function executeArbitrage(address tokenToBorrow, uint256 amount, address tokenToSwap) external onlyOwner {
        // Prepare data to be passed to receiveFlashLoan
        bytes memory userData = abi.encode(tokenToSwap);

        // Setup tokens and amounts for flash loan
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(tokenToBorrow);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        // Execute the flash loan
        IVault(balancerVault).flashLoan(
            this, // Flash loan recipient (this contract)
            tokens, // Token to flash loan
            amounts, // Amount to flash loan
            userData // User data to pass to the callback
        );
    }

    /**
     * @notice This function is called after the contract receives the flash loaned amount from Balancer
     * @param tokens Array of token addresses received
     * @param amounts Array of amounts for each token
     * @param feeAmounts Array of fee amounts to be paid for each token
     * @param userData Additional data passed to the callback
     *
     * @dev Currently Balancer fees are 0.
     */
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    )
        external
        override
    {
        if (msg.sender != balancerVault) {
            revert FlashLoanArbitrage__NotBalancerVault();
        }

        // Decode parameters
        (address tokenToSwap) = abi.decode(userData, (address));

        // Calculate the amount to be repaid (amount + fee)
        uint256 amountToRepay = amounts[0] + feeAmounts[0];

        // Perform arbitrage between DEXes
        // performArbitrage(address(tokens[0]), tokenToSwap, amounts[0]);

        // Make sure we have enough to repay the loan plus fee
        uint256 balance = tokens[0].balanceOf(address(this));

        if (balance < amountToRepay) {
            revert FlashLoanArbitrage__NotEnoughToRepayFlashLoan();
        }

        // Approve the Balancer Vault to pull the tokens back
        tokens[0].approve(balancerVault, amountToRepay);
    }

    /**
     * @dev Gets the pair price from a Uniswap V2 fork DEX
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param amountIn Amount of input tokens
     * @return amountOut Amount of output tokens
     */
    function getDEXPrice(
        uint256 dexIndex,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    )
        internal
        view
        returns (uint256 amountOut)
    {
        IUniswapV2Factory factory = IUniswapV2Factory(dexFactories[dexIndex]);
        IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(tokenIn, tokenOut));

        // Liquidity pool does not exist
        if (address(pair) == address(0)) {
            return 0;
        }

        // Gets Liquidity pool reserves
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();

        uint256 reserveIn;
        uint256 reserveOut;

        // Reserves are ordered by token address
        // This means that the token with the lower address is reserve0
        if (tokenIn < tokenOut) {
            reserveIn = reserve0;
            reserveOut = reserve1;
        } else {
            reserveIn = reserve1;
            reserveOut = reserve0;
        }

        // Calculate the price using the constant product formula
        // 0.3% fee: https://docs.uniswap.org/contracts/v2/concepts/advanced-topics/fees
        // Proudct formula: x * y = k => (tokenAReserve + amountIn * 0.997) * (tokenB - amountOut) = k
        // https://docs.uniswap.org/contracts/v2/concepts/protocol-overview/glossary#constant-product-formula
        amountOut = (amountIn * 997 * reserveOut) / ((reserveIn * 1000) + (amountIn * 997));
    }
}
