// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceSource, IPushDai} from "./interfaces/IPriceSource.sol";
import {Constituents} from "./libraries/Constituents.sol";

/// @notice Admin USD prices for a chain that has no constituent pools yet.
///         `pushDaiPerToken` converts DAI-per-token with the stored DAI price, so AKT and RITUAL
///         still go through the index push path.
contract ManualPriceSource is IPriceSource, IPushDai {
    address public admin;
    address public index;

    mapping(bytes32 => uint256) private px;
    mapping(bytes32 => bool) private has;

    error NotAdmin();

    constructor(address admin_) {
        require(admin_ != address(0), "admin");
        admin = admin_;
    }

    function setIndex(address index_) external {
        if (msg.sender != admin) revert NotAdmin();
        require(index == address(0) && index_ != address(0), "index");
        index = index_;
    }

    function setUsd(bytes32 constituent, uint256 price) external {
        if (msg.sender != admin) revert NotAdmin();
        require(Constituents.isKnown(constituent), "constituent");
        require(price > 0, "zero");
        px[constituent] = price;
        has[constituent] = true;
    }

    function usdPrice(bytes32 constituent) external view returns (uint256 price, bool ok) {
        return (px[constituent], has[constituent]);
    }

    function pushDaiPerToken(bytes32 constituent, uint256 daiPerWholeToken) external {
        require(msg.sender == admin || msg.sender == index, "admin");
        require(Constituents.isPush(constituent), "push");
        require(daiPerWholeToken > 0 && has[Constituents.DAI], "dai");
        px[constituent] = daiPerWholeToken * px[Constituents.DAI] / 1e18;
        has[constituent] = true;
    }
}
