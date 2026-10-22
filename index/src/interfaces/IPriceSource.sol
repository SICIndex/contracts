// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice USD price of one whole token, scaled by 1e18. `ok` is false when the source has no price.
interface IPriceSource {
    function usdPrice(bytes32 constituent) external view returns (uint256 price, bool ok);
}

/// @notice Admin push for AKT and RITUAL, in DAI per one whole token, scaled by 1e18.
interface IPushDai {
    function pushDaiPerToken(bytes32 constituent, uint256 daiPerWholeToken) external;
}
