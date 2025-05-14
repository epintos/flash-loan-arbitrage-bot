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


