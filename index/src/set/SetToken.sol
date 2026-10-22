// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Controller} from "./Controller.sol";

/// @notice Set Protocol v2 set token. One share is a claim on the component balances.
///         `getDefaultPositionRealUnit` is component base units per 1e18 shares.
///         The position multiplier starts at 1e18, so real units equal virtual units.
contract SetToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    Controller public immutable controller;
    address public manager;
    address public immutable creator;
    int256 public positionMultiplier = 1e18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address[] internal components;
    mapping(address => int256) internal virtualUnit;
    mapping(address => bool) public isComponent;
    mapping(address => uint256) internal componentIndex;
    mapping(address => bool) public isInitializedModule;
    bool private initialized;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    error NotCreator();
    error NotModule();
    error BadComponent();
    error AlreadyInitialized();

    constructor(Controller controller_, address manager_, string memory name_, string memory symbol_) {
        require(address(controller_) != address(0) && manager_ != address(0), "zero");
        controller = controller_;
        manager = manager_;
        creator = msg.sender;
        name = name_;
        symbol = symbol_;
    }

    /// @notice Called by the creator in the same transaction as deployment.
    function initialize(address[] calldata componentList, int256[] calldata units, address[] calldata /*modules*/ )
        external
    {
        if (msg.sender != creator) revert NotCreator();
        if (initialized) revert AlreadyInitialized();
        require(componentList.length == units.length, "len");
        initialized = true;
        for (uint256 i; i < componentList.length; i++) {
            _add(componentList[i]);
            require(units[i] > 0, "unit");
            virtualUnit[componentList[i]] = units[i];
        }
    }

    function setManager(address next) external {
        require(msg.sender == manager, "manager");
        require(next != address(0), "zero");
        manager = next;
    }

    function initializeModule() external {
        if (!controller.isModule(msg.sender)) revert NotModule();
        require(!isInitializedModule[msg.sender], "module");
        isInitializedModule[msg.sender] = true;
    }

    function mint(address to, uint256 quantity) external {
        if (!isInitializedModule[msg.sender]) revert NotModule();
        require(to != address(0) && quantity > 0, "mint");
        totalSupply += quantity;
        balanceOf[to] += quantity;
        emit Transfer(address(0), to, quantity);
    }

    function burn(address from, uint256 quantity) external {
        if (!isInitializedModule[msg.sender]) revert NotModule();
        require(quantity > 0 && balanceOf[from] >= quantity, "burn");
        balanceOf[from] -= quantity;
        totalSupply -= quantity;
        emit Transfer(from, address(0), quantity);
    }

    /// @notice A module calls out as the set. Used to move component tokens during redeem and rebalance.
    function invoke(address target, uint256 value, bytes calldata data) external returns (bytes memory) {
        if (!isInitializedModule[msg.sender]) revert NotModule();
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        require(ok, "invoke");
        return ret;
    }

    function addComponent(address component) external {
        if (!isInitializedModule[msg.sender]) revert NotModule();
        _add(component);
    }

    function removeComponent(address component) external {
        if (!isInitializedModule[msg.sender]) revert NotModule();
        if (!isComponent[component] || virtualUnit[component] != 0) revert BadComponent();
        uint256 index = componentIndex[component];
        uint256 last = components.length - 1;
        if (index != last) {
            address moved = components[last];
            components[index] = moved;
            componentIndex[moved] = index;
        }
        components.pop();
        isComponent[component] = false;
        componentIndex[component] = 0;
    }

    function editDefaultPositionUnit(address component, int256 realUnit) external {
        if (!isInitializedModule[msg.sender]) revert NotModule();
        if (!isComponent[component] || realUnit < 0) revert BadComponent();
        // Real unit = virtual * multiplier / 1e18. Multiplier stays 1e18, so virtual is the real unit.
        virtualUnit[component] = realUnit * int256(1e18) / positionMultiplier;
    }

    function getComponents() external view returns (address[] memory) {
        return components;
    }

    function getDefaultPositionRealUnit(address component) external view returns (int256) {
        return virtualUnit[component] * positionMultiplier / 1e18;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "allowance");
            allowance[from][msg.sender] = allowed - amount;
        }
        _move(from, to, amount);
        return true;
    }

    function _add(address component) internal {
        if (component == address(0) || isComponent[component]) revert BadComponent();
        componentIndex[component] = components.length;
        components.push(component);
        isComponent[component] = true;
    }

    function _move(address from, address to, uint256 amount) internal {
        require(to != address(0), "zero");
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
