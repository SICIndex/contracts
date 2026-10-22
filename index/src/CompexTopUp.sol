// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICompexTopUp} from "./interfaces/ICompex.sol";
import {TokenLib} from "./libraries/TokenLib.sol";

/// @notice Wert target. The token never stops here: `transferFrom` delivers it to `waap`.
contract CompexTopUp is ICompexTopUp {
    function topUp(address waap, address token, uint256 amount) external {
        require(waap != address(0) && token != address(0), "zero");
        require(amount > 0, "zero");
        TokenLib.safeTransferFrom(token, msg.sender, waap, amount);
    }
}
