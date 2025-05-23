import axios from 'axios';
import * as dotenv from 'dotenv';
import { ethers } from 'ethers';
import * as fs from 'fs';
import { loadFoundryWallet } from './loadFoundryWallet';

dotenv.config({ path: '../smart-contracts/.env' });

// Load ABI files
const arbitractContractABI = JSON.parse(fs.readFileSync('./abis/FlashLoanArbitrage.json', 'utf-8'));
const erco20ABI = [
  'function balanceOf(address owner) view returns (uint256)',
];

// Types
interface Token {
  address: string;
  symbol: string;
  decimals: number;
}

interface TokenPair {
  tokenBorrow: Token;
  tokenToSwap: Token;
  amountToBorrow: ethers.BigNumber;
}

interface Config {
  providerUrl: string;
  privateKey: string;
  arbitrageContractAddress: string;
  maxFeePerGas: ethers.BigNumber;
  maxPriorityFeePerGas: ethers.BigNumber;
  minProfitUSD: number;
  tokenPairs: TokenPair[];
  pollingInterval: number;
}

interface TokenPriceResponse {
  [key: string]: {
    usd: number;
  };
}

interface TokenCache {
  price: number;
  timestamp: number;
}

interface Profitability {
  isProfitable: boolean,
  profit: ethers.BigNumber,
  profitUSD: number;
  bestPath: number;
}

const cache: { [key: string]: TokenCache } = {}; // USD Price cache storage
const CACHE_EXPIRY_TIME = 300000; // Cache expiry time in milliseconds (e.g., 5 minutes)

const WETH_ADDRESS: string = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
const LINK_ADDRESS: string = '0x514910771AF9Ca656af840dff83E8264EcF986CA';
const USDT_ADDRESS: string = '0xdAC17F958D2ee523a2206206994597C13D831ec7';
const WBTC_ADDRESS: string = '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599';

// Config
const config: Config = {
  providerUrl: process.env.MAINNET_RPC_URL!,
  privateKey: process.env.PRIVATE_KEY!,
  arbitrageContractAddress: process.env.ARBITRATE_CONTRACT_ADDRESS!,
  maxFeePerGas: ethers.utils.parseUnits('50', 'gwei'),
  maxPriorityFeePerGas: ethers.utils.parseUnits('2', 'gwei'),
  minProfitUSD: 50,
  tokenPairs: [
    {
      tokenBorrow: {
        address: WETH_ADDRESS,
        symbol: 'WETH',
        decimals: 18
      },
      tokenToSwap: {
        address: LINK_ADDRESS,
        symbol: 'LINK',
        decimals: 18
      },
      amountToBorrow: ethers.utils.parseEther('10')
    },
    {
      tokenBorrow: {
        address: USDT_ADDRESS,
        symbol: 'USDT',
        decimals: 6
      },
      tokenToSwap: {
        address: WBTC_ADDRESS,
        symbol: 'WBTC',
        decimals: 8
      },
      amountToBorrow: ethers.utils.parseUnits('10000', 6)
    }
  ],
  pollingInterval: 15000 // 15 seconds
};


let wallet;
let arbitrageContract: ethers.Contract;
let provider: ethers.providers.JsonRpcProvider;

const connectWallet = async () => {
  provider = new ethers.providers.JsonRpcProvider(config.providerUrl);
  wallet = (await loadFoundryWallet()).connect(provider);
  arbitrageContract = new ethers.Contract(
    config.arbitrageContractAddress,
    arbitractContractABI,
    wallet
  );
};

const convertToUSD = async (tokenAddress: string, amount: ethers.BigNumber, decimals: number): Promise<number> => {
  const price = await getTokenUSDValue(tokenAddress);
  return parseFloat(ethers.utils.formatUnits(amount, decimals)) * price;
};

// Function to get the USD value of a token with caching
const getTokenUSDValue = async (tokenAddress: string): Promise<number> => {
  const currentTime = Date.now();

  // Check if the token price is cached and if it hasn't expired
  if (cache[tokenAddress] && currentTime - cache[tokenAddress].timestamp < CACHE_EXPIRY_TIME) {
    return cache[tokenAddress].price;
  }

  // Fetch the token price from CoinGecko API if not cached or expired
  const coingeckoUrl = `https://api.coingecko.com/api/v3/simple/token_price/ethereum?contract_addresses=${tokenAddress}&vs_currencies=usd`;

  try {
    const response = await axios.get<TokenPriceResponse>(coingeckoUrl);
    const tokenPrice: number = response.data[tokenAddress.toLowerCase()]?.usd;

    if (tokenPrice) {
      // Cache the token price with the current timestamp
      cache[tokenAddress] = { price: tokenPrice, timestamp: currentTime };
      return tokenPrice; // Return the fetched price
    } else {
      throw new Error('Price not available for the specified token.');
    }
  } catch (error) {
    console.error('Error fetching token price:', error);
    throw new Error('Failed to fetch token price.');
  }
};

export const getFlashLoanFeeRate = async (): Promise<number | null> => {
  try {
    const rate: ethers.BigNumber = await arbitrageContract.flashLoanFeeRate();
    console.log(`Current flash loan fee rate: ${rate.toString()} bps (${Number(rate) / 100}%)`);
    return rate.toNumber();
  } catch (err: any) {
    console.error(`Error: ${err.message}`);
    return null;
  }
};

export const checkArbitrageProfitability = async (tokenPair: TokenPair): Promise<Profitability> => {
  try {
    console.log(`Checking profitability: ${tokenPair.tokenBorrow.symbol} -> ${tokenPair.tokenToSwap.symbol}`);
    const returnedValues: [ethers.BigNumber, number] = await arbitrageContract.checkArbitrageProfitability(
      tokenPair.tokenBorrow.address,
      tokenPair.tokenToSwap.address,
      tokenPair.amountToBorrow
    );
    const profit: ethers.BigNumber = returnedValues[0];
    const bestPath: number = returnedValues[1];
    if (profit.gt(0)) {
      const profitUSD: number = await convertToUSD(tokenPair.tokenBorrow.address, profit, tokenPair.tokenBorrow.decimals);
      if (profitUSD >= config.minProfitUSD) {
        return { isProfitable: true, profit, profitUSD, bestPath };
      }
    }

    return { isProfitable: false, profit, profitUSD: 0, bestPath };
  } catch (err: any) {
    throw new Error(`Profit check error: ${err.message}`);
  }
};

export const executeArbitrage = async (tokenPair: TokenPair, bestPath: number) => {
  try {
    console.log(`Executing arbitrage: ${tokenPair.tokenBorrow.symbol} -> ${tokenPair.tokenToSwap.symbol}`);
    const gasEstimate = await arbitrageContract.estimateGas.executeArbitrage(
      tokenPair.tokenBorrow.address,
      tokenPair.amountToBorrow,
      tokenPair.tokenToSwap.address,
      bestPath
    );

    const gasLimit = gasEstimate.mul(120).div(100); // Adds 20%
    const feeData = await provider.getFeeData();

    let maxPriorityFeePerGas = feeData.maxPriorityFeePerGas || config.maxFeePerGas;
    let maxFeePerGas = feeData.maxFeePerGas || config.maxPriorityFeePerGas;

    // Make sure maxFeePerGas >= maxPriorityFeePerGas
    if (maxFeePerGas.lt(maxPriorityFeePerGas)) {
      maxFeePerGas = maxPriorityFeePerGas.add(ethers.utils.parseUnits("10", "gwei"));
    }

    const tx = await arbitrageContract.executeArbitrage(
      tokenPair.tokenBorrow.address,
      tokenPair.amountToBorrow,
      tokenPair.tokenToSwap.address,
      bestPath,
      {
        gasLimit,
        maxFeePerGas: maxFeePerGas,
        maxPriorityFeePerGas: maxPriorityFeePerGas
      }
    );

    console.log(`Tx submitted: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log("Gas used:", receipt.gasUsed.toString());
    return { success: true, txHash: tx.hash };
  } catch (err: any) {
    console.error(`Execution error: ${err.message}`);
    return { success: false, error: err.message };
  }
};

const getERC20Balance = async (token: Token): Promise<string> => {
  const tokenContract = new ethers.Contract(token.address, erco20ABI, provider);

  const balance = await tokenContract.balanceOf(arbitrageContract.address);

  const formattedBalance: string = ethers.utils.formatUnits(balance, token.decimals);
  return formattedBalance;
};


const monitorArbitrageOpportunities = async (): Promise<void> => {
  await connectWallet();

  console.log('Monitoring arbitrage opportunities...');

  console.log('Checking balances...');
  for (const tokenPair of config.tokenPairs) {
    const token: Token = tokenPair.tokenBorrow;
    console.log(`Balance ${token.symbol}: ${await getERC20Balance(token)}`)
  }

  setInterval(async () => {
    console.log('Checking for opportunities...');
    for (const tokenPair of config.tokenPairs) {
      const { isProfitable, profitUSD, bestPath } = await checkArbitrageProfitability(tokenPair);

      if (isProfitable) {
        console.log(`Profitable: ${tokenPair.tokenBorrow.symbol}-${tokenPair.tokenToSwap.symbol}: $${profitUSD.toFixed(2)}`);
        const result = await executeArbitrage(tokenPair, bestPath);

        if (result.success) {
          console.log(`Executed! Tx: ${result.txHash}`);
          console.log(`New Balance ${tokenPair.tokenBorrow.symbol}: ${await getERC20Balance(tokenPair.tokenBorrow)}`)
        } else {
          console.error(`Execution failed: ${result.error}`);
        }

        await new Promise((resolve) => setTimeout(resolve, 2000));
      } else {
        console.log(`Not profitable: ${tokenPair.tokenBorrow.symbol}-${tokenPair.tokenToSwap.symbol}`);
      }
    }
  }, config.pollingInterval);
};

monitorArbitrageOpportunities().catch(err => {
  console.error(`Fatal error: ${err.message}`);
  process.exit(1);
});
