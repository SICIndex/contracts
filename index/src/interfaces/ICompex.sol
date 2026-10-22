// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICompexIndex {
    // level is 1e18-scaled points. initialized is false until the first fee is booked
    // and rebalance() has run. rebalance() reverts while total enabled notional is 0.
    function viewIndex() external view returns (uint256 level, uint64 updatedAt, bool initialized);

    function weightBps(bytes32 constituent) external view returns (uint16);

    function feeNotionalDai(bytes32 constituent) external view returns (uint256);

    function enabled(bytes32 constituent) external view returns (bool);

    // Permissionless. Caller pays gas.
    // level_t = level_{t-1} * dot(w_t, p_t) / dot(w_t, p_{t-1})
    // First success sets level to 100e18 and stores prices.
    function rebalance() external;

    event IndexUpdated(uint256 level, uint64 timestamp);
    event ConstituentToggled(bytes32 indexed id, bool enabled);
}

interface ICompexTreasury {
    // Custody of fee tokens only. notionalDai is the weight input, 1e18 DAI units.
    function bookFee(bytes32 constituent, address token, uint256 feeAmount, uint256 notionalDai)
        external;

    event FeeBooked(
        bytes32 indexed constituent, address indexed token, uint256 feeAmount, uint256 notionalDai
    );
}

interface ICompexSettle {
    struct Leg {
        bytes32 constituent;
        address spendToken;
        uint256 spendAmount;
        uint256 feeAmount;
        uint256 notionalDai;
        address payTo;
        bytes payData;
    }

    // Pulls spendToken from msg.sender (the WaaP wallet), sends feeAmount to the
    // treasury, books notionalDai, forwards the remainder to payTo with payData.
    // If rebalanceAfter, calls rebalance at the end. Reverts if quoteId was used.
    function settle(bytes32 quoteId, Leg[] calldata legs, bool rebalanceAfter) external;

    event Settled(bytes32 indexed quoteId, address indexed payer);
}

interface ICompexTopUp {
    // Wert target. Forwards the full token amount to waap in the same call.
    // Holds nothing.
    function topUp(address waap, address token, uint256 amount) external;
}

/// @notice Index credits notional when the treasury books a fee. Not part of the frozen surface.
interface INotionalWriter {
    function addNotional(bytes32 constituent, uint256 notionalDai) external;
}
