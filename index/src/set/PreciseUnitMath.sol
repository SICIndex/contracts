// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Set Protocol v2's 1e18 fixed-point multiply, rounded up.
///         BasicIssuanceModule uses this so a share is never short a component wei.
library PreciseUnitMath {
    uint256 internal constant PRECISE_UNIT = 1e18;

    function preciseMulCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        return ((a * b) - 1) / PRECISE_UNIT + 1;
    }
}
