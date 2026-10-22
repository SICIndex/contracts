// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILayerZeroEndpointV2} from "../src/interfaces/ILayerZero.sol";

contract MockEndpoint {
    uint256 public nativeFee = 0.001 ether;
    bool public failSend;
    bool public failQuote;
    uint256 public sends;

    bytes public lastMessage;
    bytes public lastOptions;
    uint32 public lastDstEid;
    bytes32 public lastReceiver;
    address public lastRefund;
    uint256 public lastValue;
    bool public lastPayInLzToken;
    bytes32 public lastGuid;

    function setNativeFee(uint256 fee) external {
        nativeFee = fee;
    }

    function setFailSend(bool value) external {
        failSend = value;
    }

    function setFailQuote(bool value) external {
        failQuote = value;
    }

    function quote(ILayerZeroEndpointV2.MessagingParams calldata, address)
        external
        view
        returns (ILayerZeroEndpointV2.MessagingFee memory)
    {
        if (failQuote) revert("quote");
        return ILayerZeroEndpointV2.MessagingFee(nativeFee, 0);
    }

    function send(ILayerZeroEndpointV2.MessagingParams calldata params, address refundAddress)
        external
        payable
        returns (ILayerZeroEndpointV2.MessagingReceipt memory)
    {
        if (failSend) revert("send");
        if (msg.value < nativeFee) revert("endpoint fee");
        sends += 1;
        lastMessage = params.message;
        lastOptions = params.options;
        lastDstEid = params.dstEid;
        lastReceiver = params.receiver;
        lastRefund = refundAddress;
        lastValue = msg.value;
        lastPayInLzToken = params.payInLzToken;
        lastGuid = keccak256(abi.encode(sends, params.dstEid));
        return ILayerZeroEndpointV2.MessagingReceipt(
            lastGuid, uint64(sends), ILayerZeroEndpointV2.MessagingFee(nativeFee, 0)
        );
    }
}

contract RecordingTarget {
    bytes public lastData;
    bytes32 public lastJob;
    bytes32 public lastIrys;
    uint256 public calls;

    function onJobDelivered(bytes32 jobId, bytes32 irysId) external {
        lastData = msg.data;
        lastJob = jobId;
        lastIrys = irysId;
        calls += 1;
    }
}

contract RevertingTarget {
    function onJobDelivered(bytes32, bytes32) external pure {
        revert("nope");
    }
}

contract FallbackTarget {
    bytes public lastData;

    fallback() external {
        lastData = msg.data;
    }
}
