// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Compute-provider payment sink. `CompexSettle` approves this contract
///         for the remainder of a leg, then calls `pull`, which takes the tokens.
contract ProviderPayee {
    event Paid(address indexed token, address indexed payer, uint256 amount);

    error TransferFailed();

    function pull(address token, uint256 amount) external {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, msg.sender, address(this), amount)
        );
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
        emit Paid(token, msg.sender, amount);
    }
}
