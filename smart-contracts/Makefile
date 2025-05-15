-include .env

.PHONY: all test deploy

build :; forge build

test :; @forge test --fork-url $(MAINNET_RPC_URL)

install :
	forge install foundry-rs/forge-std@v1.9.7 --no-git && \
	forge install openzeppelin/openzeppelin-contracts@v5.3.0 --no-git && \
	forge install balancer-labs/balancer-v2-monorepo --no-git && \
	forge install Uniswap/v2-core --no-git && \
	forge install Uniswap/v2-periphery --no-git

deploy-mainnet :
	@forge script script/Deploy.s.sol:Deploy --rpc-url $(MAINNET_RPC_URL) --account $(MAINNET_ACCOUNT) --sender $(MAINNET_ACCOUNT_ADDRESS) --broadcast -vvvv

deploy-sepolia :
	@forge script script/Deploy.s.sol:Deploy --rpc-url $(SEPOLIA_RPC_URL) --account $(SEPOLIA_ACCOUNT) --sender $(SEPOLIA_ACCOUNT_ADDRESS) --broadcast -vvvv

deploy-anvil :
	@forge script script/Deploy.s.sol:Deploy --rpc-url $(RPC_URL) --account $(ANVIL_ACCOUNT) --sender $(ANVIL_ACCOUNT_ADDRESS) --broadcast -vvvv

# 22487576 Is a block that guarantee whale accounts have the tokens we need for testing purposes
anvil-fork :
	@anvil --fork-url $(MAINNET_RPC_URL) --fork-block-number 22487576 


# This is used to change the reserves when running anvil with mainnet fork
# In case we don't have ETH for gas:
# cast rpc anvil_setBalance $ANVIL_ACCOUNT_ADDRESS 0x8ac7230489e80000 --rpc-url http://localhost:8545

# First we need to send a whale's token to our account:
# Send WETH to your test account
# cast rpc anvil_impersonateAccount 0xF977814e90dA44bFA03b6295A0616a897441aceC
# cast send 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 \
#   "transfer(address,uint256)" \
#   $ANVIL_ACCOUNT_ADDRESS \
#   30000000000000000000000 \
#   --from 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E \
#	 	--rpc-url http://localhost:8545 --unlocked
# cast rpc anvil_stopImpersonatingAccount 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E
# Send LINK to your test account
# cast rpc anvil_impersonateAccount 0xF977814e90dA44bFA03b6295A0616a897441aceC
# cast send 0x5a52E96BAcdaBb82fd05763E25335261B270Efcb \
#   "transfer(address,uint256)" \
#   $ANVIL_ACCOUNT_ADDRESS \
#   30000000000000000000000 \
#   --from 0xF977814e90dA44bFA03b6295A0616a897441aceC \
#   --rpc-url http://localhost:8545 --unlocked
# cast rpc anvil_stopImpersonatingAccount 0xF977814e90dA44bFA03b6295A0616a897441aceC

change-reserves:
	@forge script script/Interactions.s.sol:ChangeReserves --rpc-url $(RPC_URL) --account $(ANVIL_ACCOUNT) --sender $(ANVIL_ACCOUNT_ADDRESS) --broadcast -vvvv
