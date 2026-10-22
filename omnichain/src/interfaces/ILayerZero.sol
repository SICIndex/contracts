// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice The slice of LayerZero V2 Endpoint this package calls. The address is injected.
interface ILayerZeroEndpointV2 {
    struct MessagingParams {
        uint32 dstEid;
        bytes32 receiver;
        bytes message;
        bytes options;
        bool payInLzToken;
    }

    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }

    struct MessagingReceipt {
        bytes32 guid;
        uint64 nonce;
        MessagingFee fee;
    }

    struct Origin {
        uint32 srcEid;
        bytes32 sender;
        uint64 nonce;
    }

    function quote(MessagingParams calldata params, address sender)
        external
        view
        returns (MessagingFee memory fee);

    function send(MessagingParams calldata params, address refundAddress)
        external
        payable
        returns (MessagingReceipt memory receipt);
}
