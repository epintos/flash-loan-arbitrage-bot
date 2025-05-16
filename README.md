# Flash Loan Arbitrage Bot

This is an exploratory project designed to test different approaches to arbitrage using flash loans.

The current version includes a [FlashLoanArbitrage](./smart-contracts/src/FlashLoanArbitrage.sol) contract that obtains a flash loan from [Balancer V2](https://docs-v2.balancer.fi/reference/contracts/flash-loans.html) and performs an ERC20 token swap using two Uniswap V2 forks: Uniswap V2 and SushiSwap V2.

The contract exposes a method called `checkArbitrageProfitability`, which is used by the [bot](./bot/src/index.ts) to determine whether an arbitrage opportunity is profitable. If it is, the bot calls `executeArbitrage` to execute the trade using the borrowed ERC20 token. The contract initiates the loan, swaps tokens across both DEXes, repays the flash loan, and retains any profit.

## Testing

For simplicity, the bot and the contract have been tested using [Anvil](https://book.getfoundry.sh/anvil/) and an Ethereum mainnet fork. During testing, the DEX reserves were manually modified to simulate a profitable arbitrage scenario.

# Useful commands

Run the following commands in `./smart-contracts`:

Import foundry wallet. This wallet will be used for othe bot too:
```bash
  cast wallet import NAME --interactive
```

Copy and complete the following `.env` file
```bash
  cp .env.example .env
```

Install dependencies:
```
  make install
```

Test with mainnet fork:
```bash
  make test
```

Run anvil with mainnet fork:
```bash
  make anvil-fork
```

Change reserves. This requires a few previous commands mentioned in the [Makefile](./smart-contracts/Makefile)
```bash
  make change-reserves
```

Deploys:
```bash
  make deploy-anvil
  make deploy-sepolia
  make deploy-mainnet
```

Run the following commands in `./bot`:

Install dependencies:
```bash
  pnpm install
```

Generate ABI:
```bash
  pnpm update-abi
```

Start bot:
```bash
  pnpm start
```
