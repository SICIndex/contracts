// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Mintable ERC-20 for the Sepolia vault. USDT is deployed from this:
///         6 decimals, the same width the markets UI expects.
contract TestERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public owner;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    error NotOwner();

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 mintToSender) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        owner = msg.sender;
        if (mintToSender > 0) _mint(msg.sender, mintToSender);
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != owner) revert NotOwner();
        _mint(to, amount);
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
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        _move(from, to, amount);
        return true;
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _move(address from, address to, uint256 amount) internal {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
