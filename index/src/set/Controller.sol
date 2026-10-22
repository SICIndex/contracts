// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Set Protocol v2 controller. Modules mint shares. The factory registers sets.
contract Controller {
    address public owner;
    mapping(address => bool) public isModule;
    mapping(address => bool) public isFactory;
    mapping(address => bool) public isSet;

    error NotOwner();
    error NotFactory();
    error ZeroAddress();

    event ModuleAdded(address indexed module);
    event FactoryAdded(address indexed factory);
    event SetAdded(address indexed setToken);

    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroAddress();
        owner = owner_;
    }

    function addModule(address module) external {
        if (msg.sender != owner) revert NotOwner();
        if (module == address(0)) revert ZeroAddress();
        isModule[module] = true;
        emit ModuleAdded(module);
    }

    function addFactory(address factory) external {
        if (msg.sender != owner) revert NotOwner();
        if (factory == address(0)) revert ZeroAddress();
        isFactory[factory] = true;
        emit FactoryAdded(factory);
    }

    function addSet(address setToken) external {
        if (!isFactory[msg.sender]) revert NotFactory();
        if (setToken == address(0)) revert ZeroAddress();
        isSet[setToken] = true;
        emit SetAdded(setToken);
    }
}
