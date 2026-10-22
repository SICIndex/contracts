// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CompexIndex} from "../src/CompexIndex.sol";
import {CompexSettle} from "../src/CompexSettle.sol";
import {CompexTreasury} from "../src/CompexTreasury.sol";
import {FixturePrices} from "../src/FixturePrices.sol";
import {ICompexIndex, ICompexSettle, ICompexTreasury, INotionalWriter} from "../src/interfaces/ICompex.sol";
import {Constituents} from "../src/libraries/Constituents.sol";
import {BasicIssuanceModule} from "../src/set/BasicIssuanceModule.sol";
import {CompexSetIssuer} from "../src/set/CompexSetIssuer.sol";
import {ConstituentDesk} from "../src/set/ConstituentDesk.sol";
import {Controller} from "../src/set/Controller.sol";
import {ISetToken} from "../src/set/ISetToken.sol";
import {SetToken} from "../src/set/SetToken.sol";
import {SetTokenCreator} from "../src/set/SetTokenCreator.sol";
import {MockERC20, Puller} from "./Mocks.sol";

contract SetIssuerTest is Test {
    FixturePrices internal prices;
    CompexIndex internal index;
    CompexTreasury internal treasury;
    CompexSettle internal settle;
    Controller internal controller;
    SetTokenCreator internal creator;
    BasicIssuanceModule internal issuance;
    ConstituentDesk internal desk;
    CompexSetIssuer internal issuer;
    SetToken internal setToken;
    MockERC20 internal usdt;
    Puller internal puller;

    MockERC20 internal dai;
    MockERC20 internal trac;
    MockERC20 internal render;
    MockERC20 internal lpt;
    MockERC20 internal irys;
    MockERC20 internal akt;
    MockERC20 internal ritual;

    address internal buyer;
    uint256 internal quoteNonce;

    function setUp() public {
        buyer = makeAddr("buyer");
        prices = new FixturePrices(address(this));
        index = new CompexIndex(address(this), prices);
        treasury = new CompexTreasury(address(this), INotionalWriter(address(index)));
        index.setNotionalWriter(address(treasury));
        settle = new CompexSettle(ICompexTreasury(address(treasury)), ICompexIndex(address(index)));
        treasury.setSettle(address(settle));
        prices.setIndex(address(index));
        puller = new Puller();

        dai = new MockERC20();
        trac = new MockERC20();
        render = new MockERC20();
        lpt = new MockERC20();
        irys = new MockERC20();
        akt = new MockERC20();
        ritual = new MockERC20();
        usdt = new MockERC20();

        prices.setUsd(Constituents.DAI, 50e18);
        prices.setUsd(Constituents.TRAC, 0.4e18);
        prices.setUsd(Constituents.RENDER, 7e18);
        prices.setUsd(Constituents.LPT, 8e18);
        prices.setUsd(Constituents.IRYS, 0.05e18);
        prices.setUsd(Constituents.AKT, 1.5e18);
        prices.setUsd(Constituents.RITUAL, 1e18);

        _book(Constituents.DAI, 20);
        _book(Constituents.TRAC, 15);
        _book(Constituents.RENDER, 25);
        _book(Constituents.LPT, 15);
        _book(Constituents.IRYS, 15);
        _book(Constituents.AKT, 10);
        index.rebalance();

        controller = new Controller(address(this));
        creator = new SetTokenCreator(controller);
        controller.addFactory(address(creator));
        issuance = new BasicIssuanceModule();
        controller.addModule(address(issuance));

        address[] memory noneA;
        int256[] memory noneU;
        address[] memory noneM;
        address setAddr = creator.create(noneA, noneU, noneM, address(this), "Super Intelligence Compute Index", "SICI");
        setToken = SetToken(setAddr);

        desk = new ConstituentDesk(address(this), prices, address(usdt), 6);
        bytes32[7] memory fixedIds = Constituents.all();
        bytes32[] memory ids = new bytes32[](7);
        for (uint256 i; i < 7; i++) ids[i] = fixedIds[i];
        address[] memory tokens = new address[](7);
        uint8[] memory decs = new uint8[](7);
        tokens[0] = address(dai);
        tokens[1] = address(trac);
        tokens[2] = address(render);
        tokens[3] = address(lpt);
        tokens[4] = address(irys);
        tokens[5] = address(akt);
        tokens[6] = address(ritual);
        for (uint256 i; i < 7; i++) {
            decs[i] = 18;
            desk.list(tokens[i], ids[i], 18);
            MockERC20(tokens[i]).mint(address(desk), 1_000_000 ether);
        }
        usdt.mint(address(desk), 1_000_000e6);

        issuer = new CompexSetIssuer(
            address(this),
            ISetToken(setAddr),
            issuance,
            desk,
            ICompexIndex(address(index)),
            prices,
            address(usdt),
            6,
            ids,
            tokens,
            decs
        );
        controller.addModule(address(issuer));
        issuance.initialize(ISetToken(setAddr));
        issuer.register();
        issuer.sync();
    }

    function test_weights_follow_fees_and_ritual_is_out() public view {
        assertEq(index.weightBps(Constituents.DAI), 2000);
        assertEq(index.weightBps(Constituents.TRAC), 1500);
        assertEq(index.weightBps(Constituents.RENDER), 2500);
        assertEq(index.weightBps(Constituents.LPT), 1500);
        assertEq(index.weightBps(Constituents.IRYS), 1500);
        assertEq(index.weightBps(Constituents.AKT), 1000);
        assertEq(index.weightBps(Constituents.RITUAL), 0);
        assertFalse(setToken.isComponent(address(ritual)));
        assertTrue(setToken.isComponent(address(dai)));
        (uint256 level,, bool init) = index.viewIndex();
        assertTrue(init);
        assertEq(level, 100e18);
        (uint256 px, bool ok) = issuer.sharePrice();
        assertTrue(ok);
        assertEq(px, 100e18);
    }

    function test_buy_mints_a_share_and_holds_the_tokens() public {
        uint256 maxUsdt = 100e6;
        (uint256 quotedShares, uint256 quotedCost) = issuer.quoteBuy(maxUsdt);
        assertEq(quotedShares, 1e18);
        assertApproxEqAbs(quotedCost, 100e6, 10);

        usdt.mint(buyer, maxUsdt);
        vm.startPrank(buyer);
        usdt.approve(address(issuer), maxUsdt);
        uint256 shares = issuer.buyForUsdt(maxUsdt, quotedShares);
        vm.stopPrank();

        assertEq(shares, 1e18);
        assertEq(setToken.balanceOf(buyer), 1e18);
        assertEq(dai.balanceOf(address(setToken)), 0.4 ether);
        assertGt(render.balanceOf(address(setToken)), 0);
        assertEq(usdt.balanceOf(buyer), maxUsdt - quotedCost);

        (uint256 px, bool ok) = issuer.sharePrice();
        assertTrue(ok);
        assertApproxEqAbs(px, 100e18, 1e15);
    }

    function test_redeem_returns_the_basket() public {
        usdt.mint(buyer, 100e6);
        vm.startPrank(buyer);
        usdt.approve(address(issuer), 100e6);
        issuer.buyForUsdt(100e6, 1e18);
        uint256 daiBefore = dai.balanceOf(buyer);
        setToken.approve(address(issuance), 1e18);
        issuance.redeem(ISetToken(address(setToken)), 1e18, buyer);
        vm.stopPrank();

        assertEq(setToken.balanceOf(buyer), 0);
        assertEq(setToken.totalSupply(), 0);
        assertGt(dai.balanceOf(buyer), daiBefore);
        assertEq(dai.balanceOf(address(setToken)), 0);
    }

    function test_sync_moves_the_basket_when_fees_change() public {
        usdt.mint(buyer, 100e6);
        vm.startPrank(buyer);
        usdt.approve(address(issuer), 100e6);
        issuer.buyForUsdt(100e6, 1e18);
        vm.stopPrank();

        uint256 renderBefore = render.balanceOf(address(setToken));
        _book(Constituents.RENDER, 50);
        index.rebalance();
        issuer.sync();

        assertGt(index.weightBps(Constituents.RENDER), 2500);
        assertGt(render.balanceOf(address(setToken)), renderBefore);
        (uint256 px, bool ok) = issuer.sharePrice();
        assertTrue(ok);
        assertGe(px, 99e18);
        assertLe(px, 101e18);
    }

    function _book(bytes32 id, uint256 notional) internal {
        MockERC20 fee = new MockERC20();
        fee.mint(address(this), 1 ether);
        fee.approve(address(settle), 1 ether);
        ICompexSettle.Leg[] memory legs = new ICompexSettle.Leg[](1);
        legs[0] = ICompexSettle.Leg({
            constituent: id,
            spendToken: address(fee),
            spendAmount: 1 ether,
            feeAmount: 1 ether,
            notionalDai: notional,
            payTo: address(puller),
            payData: ""
        });
        quoteNonce += 1;
        settle.settle(bytes32(quoteNonce), legs, false);
    }
}
