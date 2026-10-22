// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice The Set Protocol v2 set token surface this package calls.
interface ISetToken {
    function manager() external view returns (address);
    function mint(address to, uint256 quantity) external;
    function burn(address from, uint256 quantity) external;
    function invoke(address target, uint256 value, bytes calldata data) external returns (bytes memory);
    function initializeModule() external;
    function addComponent(address component) external;
    function removeComponent(address component) external;
    function editDefaultPositionUnit(address component, int256 realUnit) external;
    function getComponents() external view returns (address[] memory);
    function getDefaultPositionRealUnit(address component) external view returns (int256);
    function isComponent(address component) external view returns (bool);
    function totalSupply() external view returns (uint256);
}
