// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISiciCluster, ISiciOracle, ISiciVault} from "./interfaces/ISici.sol";

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

/// @notice Multi-collateral cluster. Each vault is one asset. The governor can add more later.
contract SiciCluster is ISiciCluster {
    address public governor;
    ISiciOracle public immutable oracle;

    address[] public vaultList;
    mapping(address vault => bool) public listed;
    mapping(address vault => uint16) public ltvBps;
    mapping(address asset => bool) public assetListed;

    event VaultAdded(address indexed vault, address indexed asset, uint16 ltvBps);
    event LtvSet(address indexed vault, uint16 ltvBps);
    event GovernorSet(address indexed governor);

    error NotGovernor();
    error ZeroAddress();
    error BadLtv();
    error AlreadyListed();
    error NotListed();

    constructor(address oracle_, address governor_) {
        if (oracle_ == address(0) || governor_ == address(0)) revert ZeroAddress();
        oracle = ISiciOracle(oracle_);
        governor = governor_;
    }

    function setGovernor(address next) external {
        if (msg.sender != governor) revert NotGovernor();
        if (next == address(0)) revert ZeroAddress();
        governor = next;
        emit GovernorSet(next);
    }

    function vaultCount() external view returns (uint256) {
        return vaultList.length;
    }

    /// @notice List a vault. Both supply and borrow stay enabled on the vault itself.
    /// `ltvBps` is the borrow power of its collateral, out of 10_000.
    function addVault(address vault, uint16 ltv) external {
        if (msg.sender != governor) revert NotGovernor();
        if (vault == address(0)) revert ZeroAddress();
        if (ltv > 10_000) revert BadLtv();
        if (listed[vault]) revert AlreadyListed();
        address asset = ISiciVault(vault).asset();
        if (asset == address(0) || assetListed[asset]) revert AlreadyListed();
        listed[vault] = true;
        assetListed[asset] = true;
        ltvBps[vault] = ltv;
        vaultList.push(vault);
        emit VaultAdded(vault, asset, ltv);
    }

    function setLtv(address vault, uint16 ltv) external {
        if (msg.sender != governor) revert NotGovernor();
        if (!listed[vault]) revert NotListed();
        if (ltv > 10_000) revert BadLtv();
        ltvBps[vault] = ltv;
        emit LtvSet(vault, ltv);
    }

    /// @notice Collateral value times LTV must cover debt. Unpriced debt is never solvent.
    function solvent(address account) external view returns (bool) {
        uint256 credit;
        uint256 debt;
        uint256 n = vaultList.length;
        for (uint256 i = 0; i < n; i++) {
            address vault = vaultList[i];
            ISiciVault book = ISiciVault(vault);
            address asset = book.asset();
            uint256 price = oracle.priceUsd(asset);
            uint256 borrowed = book.borrows(account);
            if (price == 0) {
                if (borrowed > 0) return false;
                continue;
            }
            uint256 unit = 10 ** IERC20Decimals(asset).decimals();
            uint256 supplied = book.accountAssets(account);
            credit += (supplied * price / unit) * ltvBps[vault] / 10_000;
            debt += borrowed * price / unit;
        }
        return credit >= debt;
    }
}
