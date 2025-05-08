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
    address public balancerVault;

    // Router addresses for different Uniswap V2 Fork DEXes
    address[] public dexRouters;

    // Factory addresses for different Uniswap V2 Fork DEXes
    address[] public dexFactories;

    uint256 public SWAP_TIMEOUT = 5 minutes;
    uint256 public BALANCER_FEE = 0;

    uint256 public constant DEX_1 = 0;
    uint256 public constant DEX_2 = 1;

    constructor(
        address _balancerVault,
        address[] memory _dexRouters,
        address[] memory _dexFactories
    )
        Ownable(msg.sender)
    {
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
        performArbitrage(address(tokens[0]), tokenToSwap, amounts[0]);

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

    /**
     * @dev Performs a swap on Uniswap V2 fork DEX
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param amountIn Amount of input tokens
     */
    function swapOnDEX(uint256 dexIndex, address tokenIn, address tokenOut, uint256 amountIn) internal {
        address routerAddress = dexRouters[dexIndex];

        // Approve the router to spend tokens
        IERC20(tokenIn).approve(routerAddress, amountIn);

        // Setup the path for the swap
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        // Execute the swap
        IUniswapV2Router02(routerAddress).swapExactTokensForTokens(
            amountIn,
            0, // Accept any amount of output tokens
            path,
            address(this),
            block.timestamp + SWAP_TIMEOUT
        );
    }

    /**
     * @dev Performs the arbitrage between different DEXes
     * @param tokenBorrowed Address of the borrowed token
     * @param tokenToSwap Address of the token to swap for
     * @param amount Amount of tokens borrowed
     */
    function performArbitrage(address tokenBorrowed, address tokenToSwap, uint256 amount) internal {
        // Check price on DEX 1
        uint256 dex1SwapTokenPrice = getDEXPrice(DEX_1, tokenBorrowed, tokenToSwap, amount);

        // Check price on DEX 2
        uint256 dex2SwapTokenPrice = getDEXPrice(DEX_2, tokenBorrowed, tokenToSwap, amount);

        // Determine which DEX has a better rate
        if (dex1SwapTokenPrice > dex2SwapTokenPrice) {
            // Swap on DEX 2 first, then on DEX 1
            swapOnDEX(DEX_2, tokenBorrowed, tokenToSwap, amount);

            // Get the balance of tokenToSwap
            uint256 tokenToSwapAmount = IERC20(tokenToSwap).balanceOf(address(this));

            // Swap back on DEX 1
            swapOnDEX(DEX_1, tokenToSwap, tokenBorrowed, tokenToSwapAmount);
        } else {
            // Swap on DEX 1 first, then on DEX 2
            swapOnDEX(DEX_1, tokenBorrowed, tokenToSwap, amount);

            // Get the balance of tokenToSwap
            uint256 tokenToSwapAmount = IERC20(tokenToSwap).balanceOf(address(this));

            // Swap back on DEX 2
            swapOnDEX(DEX_2, tokenToSwap, tokenBorrowed, tokenToSwapAmount);
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
        returns (int256 profitability)
    {
        // Check price on DEX 1
        uint256 dex1SwapTokenPrice = getDEXPrice(DEX_1, tokenToBorrow, tokenToSwap, amount);

        // Check price on DEX 2
        uint256 dex2SwapTokenPrice = getDEXPrice(DEX_2, tokenToBorrow, tokenToSwap, amount);

        // Calculate potential profit (accounting for Balancer's flash loan fee)
        uint256 flashLoanFee = amount * BALANCER_FEE / 1000;

        uint256 finalAmount;

        if (dex1SwapTokenPrice > dex2SwapTokenPrice) {
            // Calculate profit from DEX 2 -> DEX 1 route
            finalAmount = getDEXPrice(DEX_1, tokenToSwap, tokenToBorrow, dex2SwapTokenPrice);
        } else {
            // Calculate profit from DEX 1 -> DEX 2 route
            finalAmount = getDEXPrice(DEX_2, tokenToSwap, tokenToBorrow, dex1SwapTokenPrice);
        }
        // Check if profitable after fees
        if (finalAmount > amount + flashLoanFee) {
            profitability = int256(finalAmount - amount - flashLoanFee);
        } else {
            profitability = -int256(amount + flashLoanFee - finalAmount);
        }
    }

    /**
     * @notice Updates the Balancer flash loan fee rate
     * @param _newFeeRate New fee rate (10 = 0.1%)
     */
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
     * @param _dexFactories Array of DEX factory addresses
     */
    function updateDEXes(address[] memory _dexRouters, address[] memory _dexFactories) external onlyOwner {
        if (_dexRouters.length != _dexFactories.length && _dexRouters.length != 2) {
            revert FlashLoanArbitrage__InvalidAmountOfRoutersAndFactories();
        }
        dexRouters = _dexRouters;
        dexFactories = _dexFactories;
    }
}
