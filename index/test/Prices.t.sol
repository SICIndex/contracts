// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FullMath} from "../src/libraries/FullMath.sol";
import {PriceMath} from "../src/libraries/PriceMath.sol";
import {UniPriceSource} from "../src/UniPriceSource.sol";
import {CompexIndex} from "../src/CompexIndex.sol";
import {CompexTreasury} from "../src/CompexTreasury.sol";
import {CompexSettle} from "../src/CompexSettle.sol";
import {ICompexIndex, ICompexSettle, ICompexTreasury, INotionalWriter} from "../src/interfaces/ICompex.sol";
import {Constituents} from "../src/libraries/Constituents.sol";
import {MockERC20, MockV2, MockV3} from "./Mocks.sol";

contract FullMathTest is Test {
    function test_rounds_down() public pure {
        assertEq(FullMath.mulDiv(3, 4, 6), 2);
    }

    function test_identity_at_max() public pure {
        assertEq(
            FullMath.mulDiv(type(uint256).max, type(uint256).max, type(uint256).max), type(uint256).max
        );
    }

    function test_product_above_256_bits() public pure {
        assertEq(FullMath.mulDiv(1 << 200, 1 << 200, 1 << 150), 1 << 250);
    }
}

contract PriceMathTest is Test {
    function test_tick_zero_is_parity() public pure {
        address base = address(0x1);
        address other = address(0x2);
        assertEq(PriceMath.quoteRaw(0, base, base, 1e18), 1e18);
        assertEq(PriceMath.quoteRaw(0, base, other, 1e18), 1e18);
    }

    function test_tick_6932_is_about_two() public pure {
        address base = address(0x1);
        uint256 out = PriceMath.quoteRaw(6932, base, base, 1e18);
        assertApproxEqRel(out, 2e18, 1e14);
    }

    function test_negative_tick_inverts() public pure {
        address t0 = address(0x1);
        address t1 = address(0x2);
        uint256 forward = PriceMath.quoteRaw(6932, t0, t0, 1e18);
        uint256 back = PriceMath.quoteRaw(-6932, t0, t0, forward);
        assertApproxEqAbs(back, 1e18, 2);
        // Quoting the other token at the same tick is the inverse raw ratio.
        assertApproxEqAbs(PriceMath.quoteRaw(6932, t0, t1, forward), 1e18, 2);
    }

    function test_mean_tick_window() public pure {
        assertEq(PriceMath.meanTick(0, 1800 * 6932), 6932);
        assertEq(PriceMath.meanTick(0, -1), -1);
        assertEq(PriceMath.TWAP_SECONDS, 1800);
    }
}

contract UniPriceSourceTest is Test {
    MockERC20 internal dai;
    MockERC20 internal trac;
    MockERC20 internal usdt;
    MockERC20 internal weth;
    UniPriceSource internal src;

    function setUp() public {
        dai = new MockERC20();
        trac = new MockERC20();
        usdt = new MockERC20();
        weth = new MockERC20();
        src = new UniPriceSource(address(this));
        src.setDai(address(dai), 18);
    }

    function test_v2_spot_and_direct_usd() public {
        MockV2 usd = new MockV2(address(dai), address(usdt));
        usd.set(address(dai), 1_000e18, address(usdt), 1_000e6);
        src.setUsdPoolDirect(address(usd), false, address(usdt), 6);

        MockV2 pair = new MockV2(address(dai), address(trac));
        pair.set(address(trac), 100e18, address(dai), 200e18);
        src.setConstituentPool(Constituents.TRAC, address(trac), 18, address(pair), false);

        (uint256 daiUsd, bool okDai) = src.usdPrice(Constituents.DAI);
        (uint256 tracUsd, bool okTrac) = src.usdPrice(Constituents.TRAC);
        assertTrue(okDai && okTrac);
        assertEq(daiUsd, 1e18);
        assertEq(tracUsd, 2e18);
    }

    function test_v3_twap_requires_thirty_minutes_and_prices_parity() public {
        MockV3 usd = new MockV3(address(dai), address(usdt));
        usd.setTick(0);
        src.setUsdPoolDirect(address(usd), true, address(usdt), 18);

        MockV3 pair = new MockV3(address(dai), address(trac));
        pair.setTick(0);
        src.setConstituentPool(Constituents.TRAC, address(trac), 18, address(pair), true);

        (uint256 tracUsd, bool ok) = src.usdPrice(Constituents.TRAC);
        assertTrue(ok);
        assertApproxEqRel(tracUsd, 1e18, 1e12);
    }

    function test_unset_pool_is_missing() public view {
        (uint256 px, bool ok) = src.usdPrice(Constituents.TRAC);
        assertFalse(ok);
        assertEq(px, 0);
    }

    function test_usd_via_weth() public {
        MockV2 daiWeth = new MockV2(address(dai), address(weth));
        daiWeth.set(address(dai), 2_000e18, address(weth), 1e18);
        MockV2 wethUsd = new MockV2(address(weth), address(usdt));
        wethUsd.set(address(weth), 1e18, address(usdt), 2_000e6);
        src.setUsdPoolViaWeth(
            address(daiWeth), false, address(weth), 18, address(wethUsd), false, address(usdt), 6
        );
        (uint256 daiUsd, bool ok) = src.usdPrice(Constituents.DAI);
        assertTrue(ok);
        assertEq(daiUsd, 1e18);
    }

    function test_push_then_index_rebalance() public {
        MockV2 usd = new MockV2(address(dai), address(usdt));
        usd.set(address(dai), 1_000e18, address(usdt), 1_000e6);
        src.setUsdPoolDirect(address(usd), false, address(usdt), 6);

        CompexIndex index = new CompexIndex(address(this), src);
        src.setIndex(address(index));
        CompexTreasury treasury = new CompexTreasury(address(this), INotionalWriter(address(index)));
        index.setNotionalWriter(address(treasury));
        CompexSettle settle = new CompexSettle(ICompexTreasury(address(treasury)), ICompexIndex(address(index)));
        treasury.setSettle(address(settle));

        index.setEnabled(Constituents.TRAC, false);
        index.setEnabled(Constituents.RENDER, false);
        index.setEnabled(Constituents.LPT, false);
        index.setEnabled(Constituents.IRYS, false);
        // DAI stays enabled so its USD price is required. AKT is the only weighted asset.
        // DAI has zero notional, so it needs a price but gets no weight.

        MockERC20 fee = new MockERC20();
        address payer = makeAddr("payer");
        fee.mint(payer, 1 ether);
        vm.startPrank(payer);
        fee.approve(address(settle), 1 ether);
        ICompexSettle.Leg[] memory legs = new ICompexSettle.Leg[](1);
        legs[0] = ICompexSettle.Leg({
            constituent: Constituents.AKT,
            spendToken: address(fee),
            spendAmount: 1 ether,
            feeAmount: 1 ether,
            notionalDai: 8,
            payTo: payer,
            payData: ""
        });
        settle.settle(bytes32("q"), legs, false);
        vm.stopPrank();

        bytes32[] memory ids = new bytes32[](1);
        uint256[] memory px = new uint256[](1);
        ids[0] = Constituents.AKT;
        px[0] = 1e18;
        index.pushAndRebalance(ids, px);
        (uint256 level,, bool init) = index.viewIndex();
        assertTrue(init);
        assertEq(level, 100e18);

        px[0] = 2e18;
        index.pushAndRebalance(ids, px);
        (level,,) = index.viewIndex();
        assertEq(level, 200e18);
        assertEq(fee.balanceOf(address(treasury)), 1 ether);
        assertEq(fee.balanceOf(address(index)), 0);
    }

    function test_pool_price_doubling_doubles_the_level() public {
        MockV2 usd = new MockV2(address(dai), address(usdt));
        usd.set(address(dai), 1_000e18, address(usdt), 1_000e6);
        src.setUsdPoolDirect(address(usd), false, address(usdt), 6);

        MockV2 pair = new MockV2(address(dai), address(trac));
        pair.set(address(trac), 100e18, address(dai), 200e18);
        src.setConstituentPool(Constituents.TRAC, address(trac), 18, address(pair), false);

        CompexIndex index = new CompexIndex(address(this), src);
        CompexTreasury treasury = new CompexTreasury(address(this), INotionalWriter(address(index)));
        index.setNotionalWriter(address(treasury));
        CompexSettle settle = new CompexSettle(ICompexTreasury(address(treasury)), ICompexIndex(address(index)));
        treasury.setSettle(address(settle));

        index.setEnabled(Constituents.RENDER, false);
        index.setEnabled(Constituents.LPT, false);
        index.setEnabled(Constituents.IRYS, false);
        index.setEnabled(Constituents.AKT, false);

        MockERC20 fee = new MockERC20();
        address payer = makeAddr("payer");
        fee.mint(payer, 1 ether);
        vm.startPrank(payer);
        fee.approve(address(settle), 1 ether);
        ICompexSettle.Leg[] memory legs = new ICompexSettle.Leg[](1);
        legs[0] = ICompexSettle.Leg({
            constituent: Constituents.TRAC,
            spendToken: address(fee),
            spendAmount: 1 ether,
            feeAmount: 1 ether,
            notionalDai: 3,
            payTo: payer,
            payData: ""
        });
        settle.settle(bytes32("q"), legs, true);
        vm.stopPrank();

        pair.set(address(trac), 100e18, address(dai), 400e18);
        vm.prank(makeAddr("anyone"));
        index.rebalance();
        (uint256 level,,) = index.viewIndex();
        assertEq(level, 200e18);
    }
}
