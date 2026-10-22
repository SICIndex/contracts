// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Operator account controller, in the shape of Euler's EVC.
/// The owner of an account can name an operator. That operator can call vaults on the account's behalf.
contract SiciEVC {
    mapping(address account => mapping(address operator => bool)) public operators;
    address public onBehalfOfAccount;

    event OperatorSet(address indexed account, address indexed operator, bool authorized);
    event Call(address indexed operator, address indexed account, address indexed target);

    error NotAuthorized();
    error ZeroAddress();

    function setAccountOperator(address account, address operator, bool authorized) external {
        if (msg.sender != account) revert NotAuthorized();
        if (operator == address(0)) revert ZeroAddress();
        operators[account][operator] = authorized;
        emit OperatorSet(account, operator, authorized);
    }

    /// @notice Run `data` on `target` as `account`. Caller must be the account or its operator.
    function call(address target, address account, uint256 value, bytes calldata data)
        external
        payable
        returns (bytes memory result)
    {
        if (target == address(0) || account == address(0)) revert ZeroAddress();
        if (msg.sender != account && !operators[account][msg.sender]) revert NotAuthorized();
        onBehalfOfAccount = account;
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        onBehalfOfAccount = address(0);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
        emit Call(msg.sender, account, target);
        return ret;
    }
}
