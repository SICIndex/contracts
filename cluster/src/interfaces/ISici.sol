// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISiciOracle {
    /// @notice USD for one whole token, scaled by 1e18. Zero means the asset is unpriced.
    function priceUsd(address asset) external view returns (uint256);
}

interface ISiciEVC {
    function onBehalfOfAccount() external view returns (address);
    function operators(address account, address operator) external view returns (bool);
}

interface ISiciVault {
    function asset() external view returns (address);
    function accountAssets(address account) external view returns (uint256);
    function borrows(address account) external view returns (uint256);
    function supplyEnabled() external view returns (bool);
    function borrowEnabled() external view returns (bool);
}

interface ISiciCluster {
    function listed(address vault) external view returns (bool);
    function solvent(address account) external view returns (bool);
}
