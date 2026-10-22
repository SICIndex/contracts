// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CompexIndex} from "../src/CompexIndex.sol";
import {CompexTreasury} from "../src/CompexTreasury.sol";
import {CompexSettle} from "../src/CompexSettle.sol";
import {CompexTopUp} from "../src/CompexTopUp.sol";
import {FixturePrices} from "../src/FixturePrices.sol";
import {ICompexIndex, ICompexSettle, ICompexTreasury, INotionalWriter} from "../src/interfaces/ICompex.sol";
import {Constituents} from "../src/libraries/Constituents.sol";
import {MockERC20, Puller} from "./Mocks.sol";

contract CompexTest is Test {
    FixturePrices internal fixture;
    CompexIndex internal index;
    CompexTreasury internal treasury;
    CompexSettle internal settle;
    CompexTopUp internal topUp;
    MockERC20 internal token;
    Puller internal puller;
    address internal payer;
    uint256 internal quoteNonce;

    uint256 internal constant ONE = 1e18;
    uint256 internal constant START = 100e18;

    function setUp() public {
        payer = makeAddr("payer");
        fixture = new FixturePrices(address(this));
        index = new CompexIndex(address(this), fixture);
        treasury = new CompexTreasury(address(this), INotionalWriter(address(index)));
        index.setNotionalWriter(address(treasury));
        settle = new CompexSettle(ICompexTreasury(address(treasury)), ICompexIndex(address(index)));
        treasury.setSettle(address(settle));
        topUp = new CompexTopUp();
        fixture.setIndex(address(index));
        token = new MockERC20();
        puller = new Puller();

        bytes32[7] memory ids = Constituents.all();
        for (uint256 i; i < ids.length; i++) {
            fixture.setUsd(ids[i], ONE);
        }
    }

    function test_ids_and_ritual_starts_disabled() public view {
        assertEq(Constituents.DAI, bytes32("DAI"));
        assertEq(Constituents.RENDER, bytes32("RENDER"));
        assertFalse(index.enabled(Constituents.RITUAL));
        assertTrue(index.enabled(Constituents.DAI));
        assertTrue(index.enabled(Constituents.AKT));
        (uint256 level, uint64 at, bool init) = index.viewIndex();
        assertEq(level, 0);
        assertEq(at, 0);
        assertFalse(init);
    }

    function test_rebalance_before_any_fee_reverts() public {
        vm.expectRevert(bytes("no fee"));
        index.rebalance();
    }

    function test_first_print_is_100() public {
        _book(Constituents.DAI, 10);
        vm.expectEmit(false, false, false, true, address(index));
        emit ICompexIndex.IndexUpdated(START, uint64(block.timestamp));
        index.rebalance();
        (uint256 level,, bool init) = index.viewIndex();
        assertEq(level, START);
        assertTrue(init);
        assertEq(index.weightBps(Constituents.DAI), 10_000);
    }

    function test_price_doubling_doubles_level() public {
        _book(Constituents.DAI, 10);
        index.rebalance();
        bytes32[7] memory ids = Constituents.all();
        for (uint256 i; i < ids.length; i++) {
            fixture.setUsd(ids[i], 2e18);
        }
        index.rebalance();
        (uint256 level,,) = index.viewIndex();
        assertEq(level, 200e18);
    }

    function test_weight_change_does_not_move_level() public {
        _book(Constituents.DAI, 10);
        index.rebalance();
        _book(Constituents.TRAC, 10);
        index.rebalance();
        (uint256 level,,) = index.viewIndex();
        assertEq(level, START);
        assertEq(index.weightBps(Constituents.DAI), 5_000);
        assertEq(index.weightBps(Constituents.TRAC), 5_000);
        assertEq(_weightSum(), 10_000);
    }

    function test_remainder_goes_to_largest_notional() public {
        _book(Constituents.DAI, 2);
        _book(Constituents.TRAC, 1);
        index.rebalance();
        assertEq(index.weightBps(Constituents.DAI), 6_667);
        assertEq(index.weightBps(Constituents.TRAC), 3_333);
        assertEq(_weightSum(), 10_000);
    }

    function test_tie_keeps_earliest_id() public {
        bytes32[7] memory ids = Constituents.all();
        index.setEnabled(Constituents.RITUAL, true);
        for (uint256 i; i < ids.length; i++) {
            _book(ids[i], 1);
        }
        index.rebalance();
        assertEq(index.weightBps(Constituents.DAI), 1_432);
        assertEq(index.weightBps(Constituents.TRAC), 1_428);
        assertEq(_weightSum(), 10_000);
    }

    function test_disabled_constituent_does_not_move_level() public {
        _book(Constituents.DAI, 5);
        _book(Constituents.RITUAL, 500);
        index.rebalance();
        assertEq(index.feeNotionalDai(Constituents.RITUAL), 500);
        assertEq(index.weightBps(Constituents.RITUAL), 0);
        fixture.setUsd(Constituents.RITUAL, 9e18);
        index.rebalance();
        (uint256 level,,) = index.viewIndex();
        assertEq(level, START);
        assertEq(index.weightBps(Constituents.DAI), 10_000);
    }

    function test_new_constituent_uses_current_price_as_previous() public {
        _book(Constituents.DAI, 5);
        index.rebalance();
        index.setEnabled(Constituents.RITUAL, true);
        fixture.setUsd(Constituents.RITUAL, 9e18);
        _book(Constituents.RITUAL, 5);
        index.rebalance();
        (uint256 level,,) = index.viewIndex();
        assertEq(level, START);
        assertEq(uint256(index.weightBps(Constituents.DAI)) + index.weightBps(Constituents.RITUAL), 10_000);
    }

    function test_missing_price_reverts() public {
        _book(Constituents.DAI, 1);
        fixture.setUsd(Constituents.AKT, 0);
        vm.expectRevert(bytes("missing price"));
        index.rebalance();
    }

    function test_only_fee_notional_on_enabled_counts() public {
        _book(Constituents.RITUAL, 20);
        vm.expectRevert(bytes("no fee"));
        index.rebalance();
    }

    function test_settle_books_fee_and_forwards_remainder() public {
        uint256 spend = 100e18;
        uint256 fee = 25e18;
        token.mint(payer, spend);
        bytes memory data = abi.encodeCall(Puller.pull, (address(token), spend - fee));
        ICompexSettle.Leg[] memory legs = new ICompexSettle.Leg[](1);
        legs[0] = ICompexSettle.Leg({
            constituent: Constituents.RENDER,
            spendToken: address(token),
            spendAmount: spend,
            feeAmount: fee,
            notionalDai: 40e18,
            payTo: address(puller),
            payData: data
        });

        vm.startPrank(payer);
        token.approve(address(settle), spend);
        vm.expectEmit(true, true, false, true, address(settle));
        emit ICompexSettle.Settled(bytes32(uint256(1)), payer);
        settle.settle(bytes32(uint256(1)), legs, false);
        vm.stopPrank();

        assertTrue(puller.called());
        assertEq(token.balanceOf(address(treasury)), fee);
        assertEq(token.balanceOf(address(puller)), spend - fee);
        assertEq(token.balanceOf(address(settle)), 0);
        assertEq(token.balanceOf(address(index)), 0);
        assertEq(index.feeNotionalDai(Constituents.RENDER), 40e18);
    }

    function test_second_settle_of_same_quote_reverts() public {
        _book(Constituents.DAI, 1);
        uint256 treasuryBal = token.balanceOf(address(treasury));
        token.mint(payer, 1 ether);
        vm.startPrank(payer);
        token.approve(address(settle), 1 ether);
        ICompexSettle.Leg[] memory legs = new ICompexSettle.Leg[](1);
        legs[0] = ICompexSettle.Leg({
            constituent: Constituents.DAI,
            spendToken: address(token),
            spendAmount: 1 ether,
            feeAmount: 1 ether,
            notionalDai: 1,
            payTo: address(puller),
            payData: ""
        });
        vm.expectRevert(bytes("used"));
        settle.settle(bytes32(uint256(1)), legs, false);
        vm.stopPrank();
        assertEq(token.balanceOf(address(treasury)), treasuryBal);
    }

    function test_settle_can_rebalance_in_the_same_call() public {
        token.mint(payer, 1 ether);
        vm.startPrank(payer);
        token.approve(address(settle), 1 ether);
        ICompexSettle.Leg[] memory legs = new ICompexSettle.Leg[](1);
        legs[0] = ICompexSettle.Leg({
            constituent: Constituents.LPT,
            spendToken: address(token),
            spendAmount: 1 ether,
            feeAmount: 1 ether,
            notionalDai: 7,
            payTo: address(puller),
            payData: ""
        });
        settle.settle(bytes32("quote"), legs, true);
        vm.stopPrank();
        (uint256 level,, bool init) = index.viewIndex();
        assertTrue(init);
        assertEq(level, START);
        assertEq(index.weightBps(Constituents.LPT), 10_000);
    }

    function test_pay_revert_does_not_keep_a_fee() public {
        token.mint(payer, 10 ether);
        vm.startPrank(payer);
        token.approve(address(settle), 10 ether);
        ICompexSettle.Leg[] memory legs = new ICompexSettle.Leg[](1);
        legs[0] = ICompexSettle.Leg({
            constituent: Constituents.DAI,
            spendToken: address(token),
            spendAmount: 10 ether,
            feeAmount: 1 ether,
            notionalDai: 1,
            payTo: address(puller),
            payData: abi.encodeCall(Puller.fail, ())
        });
        vm.expectRevert(bytes("pay"));
        settle.settle(bytes32("x"), legs, false);
        vm.stopPrank();
        assertEq(token.balanceOf(address(treasury)), 0);
        assertEq(token.balanceOf(payer), 10 ether);
        assertEq(index.feeNotionalDai(Constituents.DAI), 0);
    }

    function test_topUp_forwards_and_does_not_increase_treasury() public {
        _book(Constituents.DAI, 3);
        uint256 beforeTreasury = token.balanceOf(address(treasury));
        address waap = makeAddr("waap");
        token.mint(payer, 50e18);
        vm.startPrank(payer);
        token.approve(address(topUp), 50e18);
        topUp.topUp(waap, address(token), 50e18);
        vm.stopPrank();
        assertEq(token.balanceOf(address(treasury)), beforeTreasury);
        assertEq(token.balanceOf(address(topUp)), 0);
        assertEq(token.balanceOf(waap), 50e18);
    }

    function test_bookFee_only_settle_and_known_ids() public {
        vm.expectRevert(bytes("only settle"));
        treasury.bookFee(Constituents.DAI, address(token), 0, 1);

        token.mint(payer, 1 ether);
        vm.startPrank(payer);
        token.approve(address(settle), 1 ether);
        ICompexSettle.Leg[] memory legs = new ICompexSettle.Leg[](1);
        legs[0] = ICompexSettle.Leg({
            constituent: bytes32("NOPE"),
            spendToken: address(token),
            spendAmount: 1 ether,
            feeAmount: 1 ether,
            notionalDai: 1,
            payTo: address(puller),
            payData: ""
        });
        vm.expectRevert(bytes("constituent"));
        settle.settle(bytes32("bad"), legs, false);
        vm.stopPrank();
    }

    function test_setEnabled_is_admin_only() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(bytes("admin"));
        index.setEnabled(Constituents.RITUAL, true);

        vm.expectEmit(true, false, false, true, address(index));
        emit ICompexIndex.ConstituentToggled(Constituents.RITUAL, true);
        index.setEnabled(Constituents.RITUAL, true);
        assertTrue(index.enabled(Constituents.RITUAL));
    }

    function test_push_and_rebalance_one_transaction() public {
        _book(Constituents.AKT, 4);
        index.rebalance();
        bytes32[] memory ids = new bytes32[](1);
        uint256[] memory px = new uint256[](1);
        ids[0] = Constituents.AKT;
        px[0] = 2e18;

        vm.prank(makeAddr("stranger"));
        vm.expectRevert(bytes("admin"));
        index.pushAndRebalance(ids, px);

        index.pushAndRebalance(ids, px);
        (uint256 level,,) = index.viewIndex();
        assertEq(level, 200e18);

        ids[0] = Constituents.RENDER;
        vm.expectRevert(bytes("push"));
        index.pushAndRebalance(ids, px);
    }

    function test_stranger_can_rebalance() public {
        _book(Constituents.IRYS, 1);
        vm.prank(makeAddr("stranger"));
        index.rebalance();
        (uint256 level,, bool init) = index.viewIndex();
        assertTrue(init);
        assertEq(level, START);
    }

    function _book(bytes32 id, uint256 notional) internal {
        token.mint(payer, 1 ether);
        vm.startPrank(payer);
        token.approve(address(settle), 1 ether);
        ICompexSettle.Leg[] memory legs = new ICompexSettle.Leg[](1);
        legs[0] = ICompexSettle.Leg({
            constituent: id,
            spendToken: address(token),
            spendAmount: 1 ether,
            feeAmount: 1 ether,
            notionalDai: notional,
            payTo: address(puller),
            payData: ""
        });
        quoteNonce += 1;
        settle.settle(bytes32(quoteNonce), legs, false);
        vm.stopPrank();
    }

    function _weightSum() internal view returns (uint256 sum) {
        bytes32[7] memory ids = Constituents.all();
        for (uint256 i; i < ids.length; i++) {
            sum += index.weightBps(ids[i]);
        }
    }
}
