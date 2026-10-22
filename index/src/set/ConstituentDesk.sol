// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceSource} from "../interfaces/IPriceSource.sol";
import {TokenLib} from "../libraries/TokenLib.sol";

/// @notice Sells and buys constituent tokens for USDT at the index price source.
///         A purchase moves real tokens. The desk is the inventory, not the set.
contract ConstituentDesk {
    address public admin;
    IPriceSource public prices;
    address public usdt;
    uint8 public usdtDecimals;

    mapping(address => bytes32) public constituentOf;
    mapping(address => uint8) public decimalsOf;
    mapping(address => bool) public listed;

    error NotAdmin();
    error Unlisted();
    error Unpriced();
    error Dust();

    constructor(address admin_, IPriceSource prices_, address usdt_, uint8 usdtDecimals_) {
        require(admin_ != address(0) && address(prices_) != address(0) && usdt_ != address(0), "zero");
        require(usdtDecimals_ <= 18, "decimals");
        admin = admin_;
        prices = prices_;
        usdt = usdt_;
        usdtDecimals = usdtDecimals_;
    }

    function list(address token, bytes32 constituent, uint8 decimals_) external {
        if (msg.sender != admin) revert NotAdmin();
        require(token != address(0) && constituent != bytes32(0), "zero");
        constituentOf[token] = constituent;
        decimalsOf[token] = decimals_;
        listed[token] = true;
    }

    /// @notice USDT base units required to buy `tokenAmount` of `token`.
    function quote(address token, uint256 tokenAmount) public view returns (uint256) {
        if (!listed[token]) revert Unlisted();
        (uint256 price, bool ok) = prices.usdPrice(constituentOf[token]);
        if (!ok || price == 0) revert Unpriced();
        uint256 usd = tokenAmount * price / (10 ** uint256(decimalsOf[token]));
        return usd / (10 ** (18 - uint256(usdtDecimals)));
    }

    /// @notice Pulls USDT from the caller and sends the constituent tokens to the caller.
    function buy(address token, uint256 tokenOut) external returns (uint256 usdtIn) {
        usdtIn = quote(token, tokenOut);
        if (usdtIn == 0) revert Dust();
        TokenLib.safeTransferFrom(usdt, msg.sender, address(this), usdtIn);
        TokenLib.safeTransfer(token, msg.sender, tokenOut);
    }

    /// @notice Pulls constituent tokens from the caller and pays USDT back.
    function sell(address token, uint256 tokenIn) external returns (uint256 usdtOut) {
        usdtOut = quote(token, tokenIn);
        if (usdtOut == 0) revert Dust();
        TokenLib.safeTransferFrom(token, msg.sender, address(this), tokenIn);
        TokenLib.safeTransfer(usdt, msg.sender, usdtOut);
    }
}
