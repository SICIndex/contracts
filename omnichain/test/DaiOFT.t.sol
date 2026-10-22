// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DaiOFT} from "../src/DaiOFT.sol";
import {ILayerZeroEndpointV2} from "../src/interfaces/ILayerZero.sol";
import {MockEndpoint} from "./Mocks.sol";

contract DaiOFTTest is Test {
    MockEndpoint internal endpoint;
    DaiOFT internal token;
    uint256 internal constant MINT = 1_000_000_000 ether;

    function setUp() public {
        endpoint = new MockEndpoint();
        token = new DaiOFT(address(endpoint), MINT);
    }

    function testNameDecimalsAndMintToDeployer() public view {
        assertEq(token.name(), "Decentralized Artificial Intelligence");
        assertEq(token.symbol(), "DAI");
        assertEq(token.decimals(), 18);
        assertEq(token.balanceOf(address(this)), MINT);
        assertEq(token.totalSupply(), MINT);
    }

    function testSendBurnsAndEndpointReceivesTheMessage() public {
        uint32 dstEid = 30184;
        bytes32 peer = bytes32(uint256(uint160(address(0xBEEF))));
        token.setPeer(dstEid, peer);
        bytes32 to = bytes32(uint256(uint160(address(0xCAFE))));
        token.send{value: 0.001 ether}(dstEid, to, 5 ether, "");
        assertEq(token.balanceOf(address(this)), MINT - 5 ether);
        assertEq(endpoint.sends(), 1);
        assertEq(endpoint.lastDstEid(), dstEid);
        assertEq(endpoint.lastReceiver(), peer);
        (bytes32 sentTo, uint256 sentAmount) = abi.decode(endpoint.lastMessage(), (bytes32, uint256));
        assertEq(sentTo, to);
        assertEq(sentAmount, 5 ether);
    }

    function testLzReceiveMintsFromAPeer() public {
        uint32 srcEid = 30184;
        bytes32 peer = bytes32(uint256(uint160(address(0xBEEF))));
        token.setPeer(srcEid, peer);
        address recipient = address(0xCAFE);
        bytes memory message = abi.encode(bytes32(uint256(uint160(recipient))), uint256(7 ether));
        ILayerZeroEndpointV2.Origin memory origin = ILayerZeroEndpointV2.Origin({
            srcEid: srcEid,
            sender: peer,
            nonce: 1
        });
        vm.prank(address(endpoint));
        token.lzReceive(origin, bytes32(0), message, address(0), "");
        assertEq(token.balanceOf(recipient), 7 ether);
        assertEq(token.totalSupply(), MINT + 7 ether);
    }

    function testOnlyTheEndpointCanDeliver() public {
        vm.expectRevert(DaiOFT.NotEndpoint.selector);
        token.lzReceive(
            ILayerZeroEndpointV2.Origin({srcEid: 1, sender: bytes32(uint256(1)), nonce: 1}),
            bytes32(0),
            abi.encode(bytes32(uint256(uint160(address(this)))), uint256(1)),
            address(0),
            ""
        );
    }
}
