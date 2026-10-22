// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {JobSender} from "../src/JobSender.sol";
import {LzOptions} from "../src/LzOptions.sol";
import {MockEndpoint} from "./Mocks.sol";

contract SenderTest is Test {
    MockEndpoint internal endpoint;
    JobSender internal sender;
    address internal user = makeAddr("user");

    uint32 internal constant HUB_EID = 30184;
    uint32 internal constant DST_EID = 40161;

    function setUp() public {
        endpoint = new MockEndpoint();
        sender = new JobSender(address(endpoint), HUB_EID, address(this));
        sender.setHub(HUB_EID, bytes32(uint256(uint160(address(0xBEEF)))));
        sender.allowDst(DST_EID, true);
        vm.deal(user, 1 ether);
    }

    function testRefundsExcessAndSendsToHub() public {
        uint256 fee = endpoint.nativeFee();
        uint256 start = user.balance;
        vm.prank(user);
        sender.deliver{value: 0.4 ether}(
            bytes32("job"), bytes32("irys"), DST_EID, address(0xCAFE), bytes4(0)
        );

        assertEq(user.balance, start - fee);
        assertEq(address(sender).balance, 0);
        assertEq(endpoint.sends(), 1);
        assertEq(endpoint.lastDstEid(), HUB_EID);
        assertEq(endpoint.lastReceiver(), bytes32(uint256(uint160(address(0xBEEF)))));
        assertEq(endpoint.lastRefund(), user);
        assertEq(endpoint.lastValue(), fee);
        assertFalse(endpoint.lastPayInLzToken());
        assertEq(endpoint.lastOptions(), LzOptions.executorLzReceive(LzOptions.DEFAULT_GAS));
        assertEq(uint8(endpoint.lastOptions()[5]), 1);
    }

    function testUnderpaidReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(JobSender.Underpaid.selector, endpoint.nativeFee(), 1)
        );
        vm.prank(user);
        sender.deliver{value: 1}(
            bytes32("job"), bytes32("irys"), DST_EID, address(0xCAFE), bytes4(0)
        );
        assertEq(address(sender).balance, 0);
    }

    function testDstMustBeAllowed() public {
        vm.expectRevert(abi.encodeWithSelector(JobSender.DstNotAllowed.selector, uint32(9)));
        vm.prank(user);
        sender.deliver{value: 1 ether}(
            bytes32("job"), bytes32("irys"), 9, address(0xCAFE), bytes4(0)
        );
    }

    function testZeroContractReverts() public {
        vm.expectRevert(JobSender.ZeroContract.selector);
        vm.prank(user);
        sender.deliver{value: 1 ether}(
            bytes32("job"), bytes32("irys"), DST_EID, address(0), bytes4(0)
        );
    }
}
