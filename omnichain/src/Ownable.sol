// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract Ownable {
    address public owner;

    error NotOwner();
    error ZeroAddress();

    event OwnershipTransferred(address indexed previous, address indexed next);

    constructor(address initial) {
        if (initial == address(0)) revert ZeroAddress();
        owner = initial;
        emit OwnershipTransferred(address(0), initial);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function transferOwnership(address next) external onlyOwner {
        if (next == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, next);
        owner = next;
    }
}
