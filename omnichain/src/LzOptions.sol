// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Unordered LayerZero V2 executor options. Option type 4 is not encoded.
library LzOptions {
    /// @dev Gas limit passed to lzReceive on the destination.
    uint128 internal constant DEFAULT_GAS = 800_000;

    /// @dev TYPE_3, executor worker 1, option size 17, lzReceive option type 1, uint128 gas.
    function executorLzReceive(uint128 gas) internal pure returns (bytes memory) {
        return abi.encodePacked(uint16(3), uint8(1), uint16(17), uint8(1), gas);
    }
}
