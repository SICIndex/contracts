// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ILayerZeroEndpointV2} from "../src/interfaces/ILayerZero.sol";
import {JobReceiver} from "../src/JobReceiver.sol";
import {Payload} from "../src/Payload.sol";
import {FallbackTarget, MockEndpoint, RecordingTarget, RevertingTarget} from "./Mocks.sol";

contract ReceiverTest is Test {
    event DeliveryFailed(bytes32 indexed jobId, bytes32 irysId, address dst);
    event Delivered(bytes32 indexed jobId, bytes32 irysId, address dst);

    MockEndpoint internal endpoint;
    JobReceiver internal receiver;
    RecordingTarget internal target;
    RevertingTarget internal reverting;
    FallbackTarget internal fallbackTarget;

    bytes32 internal jobId = keccak256("brief-the-team");
    bytes32 internal irysId = bytes32(uint256(7));
    bytes32 internal hubPeer;

    function setUp() public {
        endpoint = new MockEndpoint();
        hubPeer = bytes32(uint256(uint160(address(0xBEEF))));
        receiver = new JobReceiver(address(endpoint), 30184, hubPeer, address(this));
        target = new RecordingTarget();
        reverting = new RevertingTarget();
        fallbackTarget = new FallbackTarget();
    }

    function testDestinationIsCalledWithTwoWords() public {
        _receive(5, _message(address(target), Payload.ON_JOB_DELIVERED));

        assertEq(target.calls(), 1);
        assertEq(target.lastJob(), jobId);
        assertEq(target.lastIrys(), irysId);
        assertEq(target.lastData().length, 68);
        assertEq(this.selectorOf(target.lastData()), Payload.ON_JOB_DELIVERED);
        assertEq(address(receiver).balance, 0);
    }

    function testRevertingTargetEmitsDeliveryFailed() public {
        vm.expectEmit(true, false, false, true, address(receiver));
        emit DeliveryFailed(jobId, irysId, address(reverting));

        _receive(1, _message(address(reverting), Payload.ON_JOB_DELIVERED));

        assertEq(receiver.failedIds(jobId), irysId);
        assertEq(address(receiver).balance, 0);
    }

    function testUnorderedNoncesBothDeliver() public {
        _receive(5, _message(address(target), Payload.ON_JOB_DELIVERED));
        _receive(2, _message(address(target), Payload.ON_JOB_DELIVERED));
        assertEq(target.calls(), 2);
    }

    function testCustomMethodStillPassesTwoWords() public {
        bytes4 method = 0x12345678;
        _receive(1, _message(address(fallbackTarget), method));
        assertEq(fallbackTarget.lastData().length, 68);
        assertEq(this.selectorOf(fallbackTarget.lastData()), method);
    }

    function testRejectsANonHubPeer() public {
        bytes memory message = _message(address(target), Payload.ON_JOB_DELIVERED);
        ILayerZeroEndpointV2.Origin memory origin =
            ILayerZeroEndpointV2.Origin({srcEid: 30184, sender: bytes32(uint256(1)), nonce: 1});
        vm.prank(address(endpoint));
        vm.expectRevert(JobReceiver.NotPeer.selector);
        receiver.lzReceive(origin, bytes32(0), message, address(this), "");
    }

    function testRejectsAShortPayload() public {
        ILayerZeroEndpointV2.Origin memory origin =
            ILayerZeroEndpointV2.Origin({srcEid: 30184, sender: hubPeer, nonce: 1});
        vm.prank(address(endpoint));
        vm.expectRevert();
        receiver.lzReceive(origin, bytes32(0), hex"01", address(this), "");
        assertEq(target.calls(), 0);
    }

    function selectorOf(bytes calldata data) external pure returns (bytes4) {
        return bytes4(data[:4]);
    }

    function _message(address dst, bytes4 method) internal view returns (bytes memory) {
        return abi.encode(jobId, irysId, uint32(40161), dst, method);
    }

    function _receive(uint64 nonce, bytes memory message) internal {
        ILayerZeroEndpointV2.Origin memory origin =
            ILayerZeroEndpointV2.Origin({srcEid: 30184, sender: hubPeer, nonce: nonce});
        vm.prank(address(endpoint));
        receiver.lzReceive(origin, bytes32(uint256(nonce)), message, address(endpoint), "");
    }
}
