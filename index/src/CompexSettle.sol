// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICompexIndex, ICompexSettle, ICompexTreasury} from "./interfaces/ICompex.sol";
import {TokenLib} from "./libraries/TokenLib.sol";

/// @notice Pulls a quote from the payer, books the fee, and pays the remainder with `payData`.
///         Does not keep the payer's tokens. The fee moves into the treasury inside `bookFee`.
contract CompexSettle is ICompexSettle {
    ICompexTreasury public immutable treasury;
    ICompexIndex public immutable index;

    mapping(bytes32 => bool) private used;
    uint256 private locked;

    constructor(ICompexTreasury treasury_, ICompexIndex index_) {
        require(address(treasury_) != address(0) && address(index_) != address(0), "zero");
        treasury = treasury_;
        index = index_;
    }

    function settle(bytes32 quoteId, Leg[] calldata legs, bool rebalanceAfter) external {
        require(locked == 0, "reenter");
        locked = 1;
        require(!used[quoteId], "used");
        used[quoteId] = true;

        for (uint256 i; i < legs.length; i++) {
            Leg calldata leg = legs[i];
            require(leg.feeAmount <= leg.spendAmount, "fee");
            uint256 remainder = leg.spendAmount - leg.feeAmount;
            if (leg.spendAmount > 0) {
                require(leg.spendToken != address(0), "token");
                TokenLib.safeTransferFrom(leg.spendToken, msg.sender, address(this), leg.spendAmount);
            }
            if (leg.feeAmount > 0) {
                TokenLib.safeApprove(leg.spendToken, address(treasury), leg.feeAmount);
            }
            if (leg.feeAmount > 0 || leg.notionalDai > 0) {
                treasury.bookFee(leg.constituent, leg.spendToken, leg.feeAmount, leg.notionalDai);
            }
            if (leg.feeAmount > 0) {
                TokenLib.safeApprove(leg.spendToken, address(treasury), 0);
            }
            if (remainder > 0) {
                require(leg.payTo != address(0), "payTo");
                TokenLib.safeApprove(leg.spendToken, leg.payTo, remainder);
                (bool ok,) = leg.payTo.call(leg.payData);
                require(ok, "pay");
                TokenLib.safeApprove(leg.spendToken, leg.payTo, 0);
            }
            if (leg.spendAmount > 0) {
                require(TokenLib.balanceOf(leg.spendToken, address(this)) == 0, "custody");
            }
        }

        if (rebalanceAfter) index.rebalance();
        emit Settled(quoteId, msg.sender);
        locked = 0;
    }
}
