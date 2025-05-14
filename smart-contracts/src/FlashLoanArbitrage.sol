// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

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
    address public immutable balancerVault;

    // Router addresses for different Uniswap V2 Fork DEXes
    address[2] public dexRouters;

    // Pair addresses for different Uniswap V2 Fork DEXes
    address[2] public dexPairs;

    uint256 public SWAP_TIMEOUT = 5 minutes;
    uint256 public BALANCER_FEE = 0;

    uint256 public constant DEX_1 = 0;
    uint256 public constant DEX_2 = 1;

    uint256 public constant MINIMUM_OUTPUT = 1;

    constructor(address _balancerVault, address[] memory _dexRouters, address[] memory _dexPairs) Ownable(msg.sender) {
        balancerVault = _balancerVault;
        if (_dexRouters.length != _dexPairs.length && _dexRouters.length != 2) {
            revert FlashLoanArbitrage__InvalidAmountOfRoutersAndFactories();
        }
        dexRouters[0] = _dexRouters[0];
        dexRouters[1] = _dexRouters[1];
        dexPairs[0] = _dexPairs[0];
        dexPairs[1] = _dexPairs[1];
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
        performArbitrage(address(tokens[0]), tokenToSwap, amounts[0]);

        // Make sure we have enough to repay the loan plus fee
        uint256 balance = tokens[0].balanceOf(address(this));

        if (balance < amountToRepay) {
            revert FlashLoanArbitrage__NotEnoughToRepayFlashLoan();
        }

        tokens[0].transfer(balancerVault, amountToRepay);
    }

    /**
     * @notice Gets the amount of tokenOut including fees from a Uniswap V2 fork DEX
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param amountIn Amount of input tokens
     * @return amountOut Amount of output tokens
     * @dev Uses UniSwap constant product formula x*y=k
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
        IUniswapV2Pair pair = IUniswapV2Pair(dexPairs[dexIndex]);

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

    /**
     * @dev Performs a swap on Uniswap V2 fork DEX
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param amountIn Amount of input tokens
     */
    function swapOnDEX(uint256 dexIndex, address tokenIn, address tokenOut, uint256 amountIn) internal {
        address routerAddress = dexRouters[dexIndex];

        if (IERC20(tokenIn).allowance(address(this), routerAddress) < amountIn) {
            IERC20(tokenIn).approve(routerAddress, type(uint256).max);
        }

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        IUniswapV2Router02(routerAddress).swapExactTokensForTokens(
            amountIn, MINIMUM_OUTPUT, path, address(this), block.timestamp + SWAP_TIMEOUT
        );
    }

    /**
     * @dev Performs the arbitrage between different DEXes
     * @param tokenBorrowed Address of the borrowed token
     * @param tokenToSwap Address of the token to swap for
     * @param amount Amount of tokens borrowed
     */
    function performArbitrage(address tokenBorrowed, address tokenToSwap, uint256 amount) internal {
        // Get prices for both directions
        uint256 dex1Price = getDEXPrice(DEX_1, tokenBorrowed, tokenToSwap, amount);
        uint256 dex2Price = getDEXPrice(DEX_2, tokenToSwap, tokenBorrowed, dex1Price);

        uint256 dex2PriceAlt = getDEXPrice(DEX_2, tokenBorrowed, tokenToSwap, amount);
        uint256 dex1PriceAlt = getDEXPrice(DEX_1, tokenToSwap, tokenBorrowed, dex2PriceAlt);

        // Determine which path is more profitable
        if (dex2Price > dex1PriceAlt) {
            // Path 1: DEX1 -> DEX2
            swapOnDEX(DEX_1, tokenBorrowed, tokenToSwap, amount);
            uint256 received = IERC20(tokenToSwap).balanceOf(address(this));
            swapOnDEX(DEX_2, tokenToSwap, tokenBorrowed, received);
        } else {
            // Path 2: DEX2 -> DEX1
            swapOnDEX(DEX_2, tokenBorrowed, tokenToSwap, amount);
            uint256 received = IERC20(tokenToSwap).balanceOf(address(this));
            swapOnDEX(DEX_1, tokenToSwap, tokenBorrowed, received);
        }
    }

    /**
     * @dev Function to check potential profit including flash loan fees
     * @param tokenToBorrow Address of the token to borrow
     * @param tokenToSwap Address of the token to swap for
     * @param amount Amount of tokens to borrow
     * @return profitability profit amount
     */
    function checkArbitrageProfitability(
        address tokenToBorrow,
        address tokenToSwap,
        uint256 amount
    )
        external
        view
        onlyOwner
        returns (int256 profitability)
    {
        uint256 path1Out = getDEXPrice(DEX_1, tokenToBorrow, tokenToSwap, amount);
        uint256 path1Final = getDEXPrice(DEX_2, tokenToSwap, tokenToBorrow, path1Out);

        uint256 path2Out = getDEXPrice(DEX_2, tokenToBorrow, tokenToSwap, amount);
        uint256 path2Final = getDEXPrice(DEX_1, tokenToSwap, tokenToBorrow, path2Out);

        uint256 bestFinal = path1Final > path2Final ? path1Final : path2Final;
        uint256 flashLoanFee = amount * BALANCER_FEE / 1000;

        if (bestFinal > amount + flashLoanFee) {
            profitability = int256(bestFinal - amount - flashLoanFee);
        } else {
            profitability = -int256(amount + flashLoanFee - bestFinal);
        }
    }

    /**
     * @notice Withdraw a token from this contract
     * @param token IERC20 token to withdraw
     * @param amount Amount. If amount == type(uint26).max then the whole balance is withdrawn
     */
    function withdraw(address token, uint256 amount) external onlyOwner returns (uint256 amountWithdrawn) {
        amountWithdrawn = amount;
        if (amount == type(uint256).max) {
            amountWithdrawn = IERC20(token).balanceOf(address(this));
        }
        IERC20(token).transfer(msg.sender, amountWithdrawn);
    }

    function updateBalancerFeeRate(uint256 _newFeeRate) external onlyOwner {
        BALANCER_FEE = _newFeeRate;
    }

    /**
     * @notice Updates the SWAP_TIMEOUT value
     * @param _newTimeout New timeout value
     */
    function updateSwapTimeout(uint256 _newTimeout) external onlyOwner {
        SWAP_TIMEOUT = _newTimeout;
    }

    /**
     * @notice Updates the DEXes routers and factoreies
     * @param _dexRouters Array of DEX router addresses
     * @param _dexPairs Array of DEX factory addresses
     */
    function updateDEXes(address[] memory _dexRouters, address[] memory _dexPairs) external onlyOwner {
        if (_dexRouters.length != 2 || _dexPairs.length != 2) {
            revert FlashLoanArbitrage__InvalidAmountOfRoutersAndFactories();
        }
        dexRouters[0] = _dexRouters[0];
        dexRouters[1] = _dexRouters[1];
        dexPairs[0] = _dexPairs[0];
        dexPairs[1] = _dexPairs[1];
    }
}
