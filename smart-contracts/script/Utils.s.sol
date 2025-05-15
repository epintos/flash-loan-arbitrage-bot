// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

library Utils {
    function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
        require(tokenA != tokenB, "Identical addresses");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    // https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/getting-pair-addresses
    function calculatePairAddress(
        address dexfactory,
        address token0,
        address token1,
        bytes calldata initCode
    )
        external
        pure
        returns (address)
    {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(hex"ff", dexfactory, keccak256(abi.encodePacked(token0, token1)), initCode)
                    )
                )
            )
        );
    }
}
