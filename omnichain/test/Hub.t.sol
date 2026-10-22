// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {InfernetHub} from "../src/InfernetHub.sol";
import {ILayerZeroEndpointV2} from "../src/interfaces/ILayerZero.sol";
import {LzOptions} from "../src/LzOptions.sol";
import {Payload} from "../src/Payload.sol";
import {MockEndpoint} from "./Mocks.sol";

contract HubTest is Test {
    event Undeliverable(bytes32 indexed jobId, uint256 fee, uint256 balance);
    event WorkerMustUpload(bytes32 indexed jobId, bytes32 outputHash, uint256 length);
    event OutputRecorded(bytes32 indexed jobId, bytes32 outputHash, uint256 length);

    MockEndpoint internal endpoint;
    InfernetHub internal hub;
    address internal coordinator = makeAddr("coordinator");

    uint32 internal constant SENDER_EID = 30101;
    uint32 internal constant DST_EID = 40161;
    bytes32 internal senderPeer = bytes32(uint256(uint160(address(0x1111))));
    bytes32 internal receiverPeer = bytes32(uint256(uint160(address(0x2222))));
    bytes32 internal hello;
    bytes32 internal jobId = keccak256("brief-the-team");
    bytes32 internal irysId = bytes32(uint256(9));

    function setUp() public {
        endpoint = new MockEndpoint();
        hub = new InfernetHub(address(endpoint), coordinator, SENDER_EID, senderPeer, address(this));
        hub.allowDst(DST_EID, true);
        hub.setDstPeer(DST_EID, receiverPeer);
        hello = hub.HELLO_WORLD();
    }

    function testHelloWorldIsTheOnlyContainer() public view {
        assertEq(hub.HELLO_WORLD(), bytes32("hello-world"));
        assertTrue(hub.allowedContainer(bytes32("hello-world")));
        assertFalse(hub.allowedContainer(keccak256("hello-world")));
    }

    function testSmallOutputForwardsWhenFunded() public {
        _store(irysId);
        vm.deal(address(hub), 1 ether);
        bytes memory output = hex"6869";
        _callback(output);

        (bytes32 storedIrys,,,, bytes32 outputHash, bool exists, bool sent) = hub.pending(jobId);
        assertEq(storedIrys, irysId);
        assertEq(outputHash, keccak256(output));
        assertTrue(exists);
        assertTrue(sent);
        assertEq(endpoint.sends(), 1);
        assertEq(endpoint.lastDstEid(), DST_EID);
        assertEq(endpoint.lastReceiver(), receiverPeer);
        assertFalse(endpoint.lastPayInLzToken());
        assertEq(endpoint.lastOptions(), LzOptions.executorLzReceive(LzOptions.DEFAULT_GAS));
        assertEq(uint8(endpoint.lastOptions()[5]), 1);
        assertEq(endpoint.lastMessage().length, 160);
        assertEq(address(hub).balance, 1 ether - endpoint.nativeFee());
    }

    function testLargeOutputDoesNotStoreTheBody() public {
        _store(bytes32(0));
        bytes memory output = new bytes(33);
        output[0] = 0xab;

        vm.expectEmit(true, false, false, true, address(hub));
        emit WorkerMustUpload(jobId, keccak256(output), 33);
        _callback(output);

        (,,,, bytes32 outputHash,, bool sent) = hub.pending(jobId);
        assertEq(outputHash, bytes32(0));
        assertFalse(sent);
        assertEq(endpoint.sends(), 0);
    }

    function testUnderfundedCallbackDoesNotRevert() public {
        _store(irysId);
        uint256 fee = endpoint.nativeFee();
        vm.expectEmit(true, false, false, true, address(hub));
        emit OutputRecorded(jobId, keccak256(hex"01"), 1);
        vm.expectEmit(true, false, false, true, address(hub));
        emit Undeliverable(jobId, fee, 0);
        _callback(hex"01");

        (,,,,,, bool sent) = hub.pending(jobId);
        assertFalse(sent);
        assertEq(endpoint.sends(), 0);
        assertEq(address(hub).balance, 0);
    }

    function testCommitResponseRetriesAfterFunding() public {
        _store(irysId);
        _callback(hex"01");
        assertEq(endpoint.sends(), 0);

        vm.deal(address(hub), endpoint.nativeFee());
        hub.commitResponse(jobId, irysId);
        assertEq(endpoint.sends(), 1);
        (,,,,,, bool sent) = hub.pending(jobId);
        assertTrue(sent);
    }

    function testCommitResponseSetsMissingIrysId() public {
        _store(bytes32(0));
        vm.deal(address(hub), 1 ether);
        hub.commitResponse(jobId, irysId);
        (bytes32 stored,,,,,, bool sent) = hub.pending(jobId);
        assertEq(stored, irysId);
        assertTrue(sent);
    }

    function testRejectsADifferentContainer() public {
        _store(irysId);
        vm.prank(coordinator);
        vm.expectRevert(
            abi.encodeWithSelector(InfernetHub.ContainerNotAllowed.selector, keccak256("other"))
        );
        hub.rawReceiveCompute(
            1, 1, 1, coordinator, abi.encode(jobId), hex"01", "", keccak256("other"), 0
        );
    }

    function testSendFailureDoesNotRevertTheCallback() public {
        _store(irysId);
        vm.deal(address(hub), 1 ether);
        endpoint.setFailSend(true);
        vm.expectEmit(true, false, false, true, address(hub));
        emit OutputRecorded(jobId, keccak256(hex"01"), 1);
        vm.expectEmit(true, false, false, true, address(hub));
        emit Undeliverable(jobId, endpoint.nativeFee(), 1 ether);
        _callback(hex"01");
        (,,,,,, bool sent) = hub.pending(jobId);
        assertFalse(sent);
    }

    function testInboundNonceIsNotEnforced() public {
        _storeAt(irysId, 9);
        _storeAt(bytes32(uint256(4)), 2);
        (bytes32 stored,,,,, bool exists,) = hub.pending(jobId);
        assertTrue(exists);
        assertEq(stored, bytes32(uint256(4)));
    }

    function _callback(bytes memory output) internal {
        vm.prank(coordinator);
        hub.rawReceiveCompute(1, 1, 1, coordinator, abi.encode(jobId), output, "", hello, 0);
    }

    function _store(bytes32 id) internal {
        _storeAt(id, 1);
    }

    function _storeAt(bytes32 id, uint64 nonce) internal {
        bytes memory message =
            abi.encode(jobId, id, DST_EID, address(0xCAFE), Payload.ON_JOB_DELIVERED);
        ILayerZeroEndpointV2.Origin memory origin =
            ILayerZeroEndpointV2.Origin({srcEid: SENDER_EID, sender: senderPeer, nonce: nonce});
        vm.prank(address(endpoint));
        hub.lzReceive(origin, bytes32(uint256(nonce)), message, address(endpoint), "");
    }
}
