// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISiciOracle} from "./interfaces/ISici.sol";

/// @notice Governor-set USD prices. 1e18 is one dollar per whole token.
contract ManualOracle is ISiciOracle {
    address public governor;
    mapping(address => uint256) public priceUsd;

    event PriceSet(address indexed asset, uint256 price);
    event GovernorSet(address indexed governor);

    error NotGovernor();
    error ZeroAddress();

    constructor(address governor_) {
        if (governor_ == address(0)) revert ZeroAddress();
        governor = governor_;
    }

    function setGovernor(address next) external {
        if (msg.sender != governor) revert NotGovernor();
        if (next == address(0)) revert ZeroAddress();
        governor = next;
        emit GovernorSet(next);
    }

    function setPrice(address asset, uint256 price) external {
        if (msg.sender != governor) revert NotGovernor();
        if (asset == address(0)) revert ZeroAddress();
        priceUsd[asset] = price;
        emit PriceSet(asset, price);
    }
}
