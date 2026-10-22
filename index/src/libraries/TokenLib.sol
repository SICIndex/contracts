// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Minimal} from "../interfaces/IExternal.sol";

library TokenLib {
    function balanceOf(address token, address account) internal view returns (uint256) {
        return IERC20Minimal(token).balanceOf(account);
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        _call(token, abi.encodeCall(IERC20Minimal.transferFrom, (from, to, amount)), "transferFrom");
    }

    function safeTransfer(address token, address to, uint256 amount) internal {
        _call(token, abi.encodeCall(IERC20Minimal.transfer, (to, amount)), "transfer");
    }

    /// @dev Zero the allowance first so tokens that require it (USDT) succeed.
    function safeApprove(address token, address spender, uint256 amount) internal {
        _call(token, abi.encodeCall(IERC20Minimal.approve, (spender, 0)), "approve0");
        if (amount > 0) {
            _call(token, abi.encodeCall(IERC20Minimal.approve, (spender, amount)), "approve");
        }
    }

    function _call(address token, bytes memory data, string memory why) private {
        (bool ok, bytes memory ret) = token.call(data);
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), why);
    }
}
