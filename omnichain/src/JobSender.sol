// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILayerZeroEndpointV2} from "./interfaces/ILayerZero.sol";
import {LzOptions} from "./LzOptions.sol";
import {Ownable} from "./Ownable.sol";
import {DeliveryPayload, Payload} from "./Payload.sol";

/// @notice Source-chain sender. One unordered hop carries the five-word payload to the hub.
/// @dev Excess value is returned to the caller in this transaction. The contract does not keep it.
contract JobSender is Ownable {
    ILayerZeroEndpointV2 public immutable endpoint;
    uint32 public hubEid;
    bytes32 public hubPeer;
    mapping(uint32 => bool) public allowedDst;

    error ZeroContract();
    error DstNotAllowed(uint32 eid);
    error PeerUnset();
    error Underpaid(uint256 fee, uint256 value);
    error RefundFailed();

    event Sent(bytes32 indexed jobId, bytes32 irysId, uint32 dstEid, bytes32 guid);

    constructor(address endpoint_, uint32 hubEid_, address owner_) Ownable(owner_) {
        if (endpoint_ == address(0)) revert ZeroAddress();
        endpoint = ILayerZeroEndpointV2(endpoint_);
        hubEid = hubEid_;
    }

    function setHub(uint32 eid, bytes32 peer) external onlyOwner {
        hubEid = eid;
        hubPeer = peer;
    }

    function allowDst(uint32 eid, bool allowed) external onlyOwner {
        allowedDst[eid] = allowed;
    }

    function deliver(
        bytes32 jobId,
        bytes32 irysId,
        uint32 dstEid,
        address dstContract,
        bytes4 method
    ) external payable returns (bytes32 guid) {
        if (dstContract == address(0)) revert ZeroContract();
        if (!allowedDst[dstEid]) revert DstNotAllowed(dstEid);
        if (hubPeer == bytes32(0) || hubEid == 0) revert PeerUnset();
        if (method == bytes4(0)) method = Payload.ON_JOB_DELIVERED;

        ILayerZeroEndpointV2.MessagingParams memory params = ILayerZeroEndpointV2.MessagingParams({
            dstEid: hubEid,
            receiver: hubPeer,
            message: Payload.encode(
                DeliveryPayload({
                    jobId: jobId,
                    irysId: irysId,
                    dstEid: dstEid,
                    dstContract: dstContract,
                    method: method
                })
            ),
            options: LzOptions.executorLzReceive(LzOptions.DEFAULT_GAS),
            payInLzToken: false
        });

        uint256 fee = endpoint.quote(params, address(this)).nativeFee;
        if (msg.value < fee) revert Underpaid(fee, msg.value);

        ILayerZeroEndpointV2.MessagingReceipt memory receipt =
            endpoint.send{value: fee}(params, msg.sender);
        guid = receipt.guid;

        uint256 extra = msg.value - fee;
        if (extra > 0) {
            (bool ok,) = msg.sender.call{value: extra}("");
            if (!ok) revert RefundFailed();
        }
        emit Sent(jobId, irysId, dstEid, guid);
    }
}
