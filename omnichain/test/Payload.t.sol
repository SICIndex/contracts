// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {JobSender} from "../src/JobSender.sol";
import {LzOptions} from "../src/LzOptions.sol";
import {Payload} from "../src/Payload.sol";
import {MockEndpoint} from "./Mocks.sol";

contract PayloadTest is Test {
    MockEndpoint internal endpoint;
    JobSender internal sender;

    function setUp() public {
        endpoint = new MockEndpoint();
        sender = new JobSender(address(endpoint), 30184, address(this));
        sender.setHub(30184, bytes32(uint256(uint160(address(0xBEEF)))));
        sender.allowDst(40161, true);
    }

    function testDeliverSelectorIsFiveWords() public view {
        assertEq(
            sender.deliver.selector,
            bytes4(keccak256("deliver(bytes32,bytes32,uint32,address,bytes4)"))
        );
        assertEq(Payload.ON_JOB_DELIVERED, bytes4(keccak256("onJobDelivered(bytes32,bytes32)")));
    }

    /// @dev Calling the five-argument form is the compile lock. A sixth parameter does not typecheck.
    function testEncodedPayloadHasNoSixthWord() public {
        bytes32 jobId = bytes32(uint256(1));
        bytes32 irysId = bytes32(uint256(2));
        sender.deliver{value: endpoint.nativeFee()}(
            jobId, irysId, 40161, address(0xCAFE), bytes4(0)
        );

        bytes memory message = endpoint.lastMessage();
        assertEq(message.length, 160);
        (bytes32 gotJob, bytes32 gotIrys, uint32 dstEid, address dst, bytes4 method) =
            abi.decode(message, (bytes32, bytes32, uint32, address, bytes4));
        assertEq(gotJob, jobId);
        assertEq(gotIrys, irysId);
        assertEq(dstEid, 40161);
        assertEq(dst, address(0xCAFE));
        assertEq(method, Payload.ON_JOB_DELIVERED);

        vm.expectRevert();
        this.decodeSixth(message);
    }

    function decodeSixth(bytes calldata message) external pure {
        abi.decode(message, (bytes32, bytes32, uint32, address, bytes4, bytes));
    }

    function testOptionsAreUnorderedLzReceive() public pure {
        bytes memory options = LzOptions.executorLzReceive(LzOptions.DEFAULT_GAS);
        assertEq(options.length, 22);
        assertEq(uint8(options[0]), 0);
        assertEq(uint8(options[1]), 3);
        assertEq(uint8(options[2]), 1);
        assertEq(uint8(options[5]), 1);
    }
}
