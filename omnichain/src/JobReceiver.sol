// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILayerZeroEndpointV2} from "./interfaces/ILayerZero.sol";
import {DeliveryPayload, Payload} from "./Payload.sol";

/// @notice Destination receiver. The hub is the only peer.
/// @dev The target is called with exactly two bytes32 words. A revert there is stored, not bubbled.
contract JobReceiver {
    uint256 public constant CALL_GAS = 500_000;

    ILayerZeroEndpointV2 public immutable endpoint;
    uint32 public hubEid;
    bytes32 public hubPeer;
    address public owner;

    mapping(bytes32 => bytes32) public failedIds;

    error NotEndpoint();
    error NotPeer();
    error NotOwner();
    error ZeroAddress();

    event Delivered(bytes32 indexed jobId, bytes32 irysId, address dst);
    event DeliveryFailed(bytes32 indexed jobId, bytes32 irysId, address dst);

    constructor(address endpoint_, uint32 hubEid_, bytes32 hubPeer_, address owner_) {
        if (endpoint_ == address(0) || owner_ == address(0)) revert ZeroAddress();
        endpoint = ILayerZeroEndpointV2(endpoint_);
        hubEid = hubEid_;
        hubPeer = hubPeer_;
        owner = owner_;
    }

    function setHubPeer(bytes32 peer) external {
        if (msg.sender != owner) revert NotOwner();
        hubPeer = peer;
    }

    function lzReceive(
        ILayerZeroEndpointV2.Origin calldata origin,
        bytes32 guid,
        bytes calldata message,
        address executor,
        bytes calldata extraData
    ) external payable {
        if (msg.sender != address(endpoint)) revert NotEndpoint();
        if (origin.srcEid != hubEid || origin.sender != hubPeer) revert NotPeer();
        guid;
        executor;
        extraData;

        DeliveryPayload memory payload = Payload.decode(message);
        bytes4 method = payload.method == bytes4(0) ? Payload.ON_JOB_DELIVERED : payload.method;
        bytes memory data = abi.encodeWithSelector(method, payload.jobId, payload.irysId);

        (bool ok,) = payload.dstContract.call{gas: CALL_GAS}(data);
        if (ok) {
            emit Delivered(payload.jobId, payload.irysId, payload.dstContract);
        } else {
            failedIds[payload.jobId] = payload.irysId;
            emit DeliveryFailed(payload.jobId, payload.irysId, payload.dstContract);
        }
    }
}
