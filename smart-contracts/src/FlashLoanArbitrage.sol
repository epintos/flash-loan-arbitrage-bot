// SDPX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import { IVault } from "@balancer-labs/v2-interfaces/vault/IVault.sol";
import { IFlashLoanRecipient } from "@balancer-labs/v2-interfaces/vault/IFlashLoanRecipient.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@balancer-labs/v2-interfaces/solidity-utils/openzeppelin/IERC20.sol";

contract FlashLoanArbitrage is IFlashLoanRecipient, Ownable {
    error FlashLoanArbitrage__NotBalancerVault();
    error FlashLoanArbitrage__NotEnoughToRepayFlashLoan();

    // Address of the Balancer Vault for flash loans
    address private balancerVault;

    // Router addresses for different DEXes
    address private uniswapRouter;
    address private sushiswapRouter;

    // Factory addresses for different DEXes
    address private uniswapFactory;
    address private sushiswapFactory;

    constructor(
        address _balancerVault,
        address _uniswapRouter,
        address _uniswapFactory,
        address _sushiswapRouter,
        address _sushiswapFactory
    )
        Ownable(msg.sender)
    {
        balancerVault = _balancerVault;
        uniswapRouter = _uniswapRouter;
        uniswapFactory = _uniswapFactory;
        sushiswapRouter = _sushiswapRouter;
        sushiswapFactory = _sushiswapFactory;
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
}
