// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceSource, IPushDai} from "./interfaces/IPriceSource.sol";
import {Constituents} from "./libraries/Constituents.sol";

/// @notice Test and local price source. One USD number per constituent, set by the caller.
///         Push treats DAI as $1, so the pushed DAI-per-token value is stored as the USD price.
///         This contract is not a production oracle.
contract FixturePrices is IPriceSource, IPushDai {
    address public admin;
    address public index;

    mapping(bytes32 => uint256) private px;
    mapping(bytes32 => bool) private has;

    constructor(address admin_) {
        require(admin_ != address(0), "admin");
        admin = admin_;
    }

    function setIndex(address index_) external {
        require(msg.sender == admin, "admin");
        require(index == address(0), "once");
        index = index_;
    }

    function setUsd(bytes32 constituent, uint256 price) external {
        px[constituent] = price;
        has[constituent] = price > 0;
    }

    function usdPrice(bytes32 constituent) external view returns (uint256 price, bool ok) {
        return (px[constituent], has[constituent]);
    }

    function pushDaiPerToken(bytes32 constituent, uint256 daiPerWholeToken) external {
        require(msg.sender == admin || msg.sender == index, "admin");
        require(Constituents.isPush(constituent), "push");
        require(daiPerWholeToken > 0, "zero");
        px[constituent] = daiPerWholeToken;
        has[constituent] = true;
    }
}
