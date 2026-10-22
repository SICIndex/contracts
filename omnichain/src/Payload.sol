// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Five static words. A sixth field would change deliver's selector and this length.
struct DeliveryPayload {
    bytes32 jobId;
    bytes32 irysId;
    uint32 dstEid;
    address dstContract;
    bytes4 method;
}

library Payload {
    /// @dev Selector of onJobDelivered(bytes32,bytes32).
    bytes4 internal constant ON_JOB_DELIVERED =
        bytes4(keccak256("onJobDelivered(bytes32,bytes32)"));

    uint256 internal constant ENCODED_LENGTH = 160;

    error BadLength(uint256 length);

    function encode(DeliveryPayload memory payload) internal pure returns (bytes memory) {
        return abi.encode(
            payload.jobId, payload.irysId, payload.dstEid, payload.dstContract, payload.method
        );
    }

    function decode(bytes calldata message) internal pure returns (DeliveryPayload memory payload) {
        if (message.length != ENCODED_LENGTH) revert BadLength(message.length);
        (payload.jobId, payload.irysId, payload.dstEid, payload.dstContract, payload.method) =
            abi.decode(message, (bytes32, bytes32, uint32, address, bytes4));
    }
}
