// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICompexTreasury, INotionalWriter} from "./interfaces/ICompex.sol";
import {Constituents} from "./libraries/Constituents.sol";
import {TokenLib} from "./libraries/TokenLib.sol";

/// @notice Holds fee tokens and nothing else. The settle module is the only caller of `bookFee`.
contract CompexTreasury is ICompexTreasury {
    address public admin;
    address public settle;
    INotionalWriter public immutable index;

    constructor(address admin_, INotionalWriter index_) {
        require(admin_ != address(0) && address(index_) != address(0), "zero");
        admin = admin_;
        index = index_;
    }

    function setSettle(address settle_) external {
        require(msg.sender == admin, "admin");
        require(settle == address(0), "once");
        require(settle_ != address(0), "zero");
        settle = settle_;
    }

    function bookFee(bytes32 constituent, address token, uint256 feeAmount, uint256 notionalDai)
        external
    {
        require(msg.sender == settle, "only settle");
        require(Constituents.isKnown(constituent), "constituent");
        require(token != address(0) || feeAmount == 0, "token");
        if (feeAmount > 0) {
            uint256 beforeBal = TokenLib.balanceOf(token, address(this));
            TokenLib.safeTransferFrom(token, msg.sender, address(this), feeAmount);
            require(TokenLib.balanceOf(token, address(this)) - beforeBal >= feeAmount, "fee in");
        }
        if (notionalDai > 0) index.addNotional(constituent, notionalDai);
        emit FeeBooked(constituent, token, feeAmount, notionalDai);
    }
}
