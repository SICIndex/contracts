// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILayerZeroEndpointV2} from "./interfaces/ILayerZero.sol";
import {LzOptions} from "./LzOptions.sol";
import {Ownable} from "./Ownable.sol";
import {DeliveryPayload, Payload} from "./Payload.sol";

/// @notice Base hub. The hello-world callback proves the hop. Providers do not run here.
/// @dev A short output is stored as a hash. A long output is left for an off-chain worker.
///      The callback does not upload to Irys. An underfunded forward emits Undeliverable and returns.
contract InfernetHub is Ownable {
    uint256 internal constant SMALL_OUTPUT = 32;

    /// @dev Left-aligned "hello-world". This is the only container allowed at construction.
    bytes32 public constant HELLO_WORLD = bytes32("hello-world");

    struct Pending {
        bytes32 irysId;
        uint32 dstEid;
        address dstContract;
        bytes4 method;
        bytes32 outputHash;
        bool exists;
        bool sent;
    }

    ILayerZeroEndpointV2 public immutable endpoint;
    address public coordinator;
    uint32 public senderEid;
    bytes32 public senderPeer;

    mapping(uint32 => bool) public allowedDst;
    mapping(uint32 => bytes32) public dstPeer;
    mapping(bytes32 => bool) public allowedContainer;
    mapping(bytes32 => Pending) public pending;

    error NotEndpoint();
    error NotPeer();
    error NotCoordinator();
    error ContainerNotAllowed(bytes32 id);
    error BadInput();
    error UnknownJob();
    error AlreadySent();
    error ZeroIrys();

    event ProofRequested(bytes32 indexed jobId, bytes32 containerId);
    event OutputRecorded(bytes32 indexed jobId, bytes32 outputHash, uint256 length);
    event WorkerMustUpload(bytes32 indexed jobId, bytes32 outputHash, uint256 length);
    event Committed(bytes32 indexed jobId, bytes32 irysId);
    event Forwarded(bytes32 indexed jobId, bytes32 irysId, uint32 dstEid, bytes32 guid);
    event Undeliverable(bytes32 indexed jobId, uint256 fee, uint256 balance);
    event UnknownCallback(bytes32 indexed jobId);

    constructor(
        address endpoint_,
        address coordinator_,
        uint32 senderEid_,
        bytes32 senderPeer_,
        address owner_
    ) Ownable(owner_) {
        if (endpoint_ == address(0)) revert ZeroAddress();
        endpoint = ILayerZeroEndpointV2(endpoint_);
        coordinator = coordinator_;
        senderEid = senderEid_;
        senderPeer = senderPeer_;
        allowedContainer[HELLO_WORLD] = true;
    }

    /// @dev Operator float for the forward fee. This is not a user deposit.
    receive() external payable {}

    function setCoordinator(address next) external onlyOwner {
        if (next == address(0)) revert ZeroAddress();
        coordinator = next;
    }

    function setSender(uint32 eid, bytes32 peer) external onlyOwner {
        senderEid = eid;
        senderPeer = peer;
    }

    function allowDst(uint32 eid, bool allowed) external onlyOwner {
        allowedDst[eid] = allowed;
    }

    function setDstPeer(uint32 eid, bytes32 peer) external onlyOwner {
        dstPeer[eid] = peer;
    }

    function allowContainer(bytes32 id, bool allowed) external onlyOwner {
        if (id == bytes32(0)) revert ZeroAddress();
        allowedContainer[id] = allowed;
    }

    function lzReceive(
        ILayerZeroEndpointV2.Origin calldata origin,
        bytes32 guid,
        bytes calldata message,
        address executor,
        bytes calldata extraData
    ) external payable {
        if (msg.sender != address(endpoint)) revert NotEndpoint();
        if (origin.srcEid != senderEid || origin.sender != senderPeer) revert NotPeer();
        guid;
        executor;
        extraData;

        DeliveryPayload memory payload = Payload.decode(message);
        Pending storage job = pending[payload.jobId];
        if (job.sent) return;

        job.irysId = payload.irysId;
        job.dstEid = payload.dstEid;
        job.dstContract = payload.dstContract;
        job.method = payload.method == bytes4(0) ? Payload.ON_JOB_DELIVERED : payload.method;
        job.exists = true;
        emit ProofRequested(payload.jobId, HELLO_WORLD);
    }

    /// @notice Infernet coordinator entry. Nine arguments, matching the hello-world callback shape.
    function rawReceiveCompute(
        uint32 subscriptionId,
        uint32 interval,
        uint16 redundancy,
        address node,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof,
        bytes32 containerId,
        uint256 index
    ) external {
        if (msg.sender != coordinator) revert NotCoordinator();
        if (!allowedContainer[containerId]) revert ContainerNotAllowed(containerId);
        subscriptionId;
        interval;
        redundancy;
        node;
        proof;
        index;
        if (input.length != 32) revert BadInput();

        bytes32 jobId = abi.decode(input, (bytes32));
        Pending storage job = pending[jobId];
        if (!job.exists) {
            emit UnknownCallback(jobId);
            return;
        }

        bytes32 outputHash = keccak256(output);
        if (output.length <= SMALL_OUTPUT) {
            job.outputHash = outputHash;
            emit OutputRecorded(jobId, outputHash, output.length);
        } else {
            emit WorkerMustUpload(jobId, outputHash, output.length);
        }

        if (job.irysId != bytes32(0) && !job.sent) _send(jobId);
    }

    /// @notice Worker entry after an off-chain upload. Sends when the hop can be paid.
    function commitResponse(bytes32 jobId, bytes32 irysId) external onlyOwner {
        Pending storage job = pending[jobId];
        if (!job.exists) revert UnknownJob();
        if (job.sent) revert AlreadySent();
        if (job.irysId == bytes32(0)) {
            if (irysId == bytes32(0)) revert ZeroIrys();
            job.irysId = irysId;
            emit Committed(jobId, irysId);
        }
        _send(jobId);
    }

    function _send(bytes32 jobId) internal {
        Pending storage job = pending[jobId];
        bytes32 peer = dstPeer[job.dstEid];
        if (job.sent || job.irysId == bytes32(0) || !allowedDst[job.dstEid] || peer == bytes32(0)) {
            emit Undeliverable(jobId, 0, address(this).balance);
            return;
        }

        ILayerZeroEndpointV2.MessagingParams memory params = _params(jobId, peer);
        try endpoint.quote(params, address(this)) returns (
            ILayerZeroEndpointV2.MessagingFee memory quoted
        ) {
            _sendQuoted(jobId, params, quoted.nativeFee);
        } catch {
            emit Undeliverable(jobId, 0, address(this).balance);
        }
    }

    function _params(bytes32 jobId, bytes32 peer)
        internal
        view
        returns (ILayerZeroEndpointV2.MessagingParams memory)
    {
        Pending storage job = pending[jobId];
        return ILayerZeroEndpointV2.MessagingParams({
            dstEid: job.dstEid,
            receiver: peer,
            message: Payload.encode(
                DeliveryPayload({
                    jobId: jobId,
                    irysId: job.irysId,
                    dstEid: job.dstEid,
                    dstContract: job.dstContract,
                    method: job.method
                })
            ),
            options: LzOptions.executorLzReceive(LzOptions.DEFAULT_GAS),
            payInLzToken: false
        });
    }

    function _sendQuoted(
        bytes32 jobId,
        ILayerZeroEndpointV2.MessagingParams memory params,
        uint256 fee
    ) internal {
        if (address(this).balance < fee) {
            emit Undeliverable(jobId, fee, address(this).balance);
            return;
        }
        try endpoint.send{value: fee}(params, address(this)) returns (
            ILayerZeroEndpointV2.MessagingReceipt memory receipt
        ) {
            pending[jobId].sent = true;
            emit Forwarded(jobId, pending[jobId].irysId, params.dstEid, receipt.guid);
        } catch {
            emit Undeliverable(jobId, fee, address(this).balance);
        }
    }
}
