// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriceMath} from "../src/libraries/PriceMath.sol";
import {UniPriceSource} from "../src/UniPriceSource.sol";
import {TwapPool} from "../src/TwapPool.sol";
import {Constituents} from "../src/libraries/Constituents.sol";
import {MockERC20} from "./Mocks.sol";

contract TwapPoolTest is Test {
    function test_quote_matches_deploy_script() public pure {
        assertEq(PriceMath.quoteRaw(0, address(2), address(2), 1e18), 1e18);
        assertEq(PriceMath.quoteRaw(1000, address(2), address(2), 1e18), 1_105_165_392_603_232_696);
        assertEq(PriceMath.quoteRaw(-200_000, address(2), address(2), 1e18), 2_063_215_669);
    }

    function test_one_dai_quotes_fifty_usdt() public {
        MockERC20 dai = new MockERC20();
        MockERC20 usdt = new MockERC20();
        int24 tick = address(dai) < address(usdt) ? int24(-237_202) : int24(237_202);
        TwapPool pool = new TwapPool(address(dai), address(usdt), 6, tick);

        UniPriceSource src = new UniPriceSource(address(this));
        src.setDai(address(dai), 18);
        src.setUsdPoolDirect(address(pool), true, address(usdt), 6);

        (uint256 px, bool ok) = src.usdPrice(Constituents.DAI);
        assertTrue(ok);
        assertApproxEqRel(px, 50e18, 1e14);

        uint32[] memory ago = new uint32[](2);
        ago[0] = 1800;
        ago[1] = 0;
        (int56[] memory cumulatives,) = pool.observe(ago);
        assertEq(PriceMath.meanTick(cumulatives[0], cumulatives[1]), tick);
    }

    function test_supply_keeps_the_one_to_fifty_ratio() public {
        MockERC20 dai = new MockERC20();
        MockERC20 usdt = new MockERC20();
        TwapPool pool = new TwapPool(address(dai), address(usdt), 6, -237_202);
        dai.mint(address(this), 20e18);
        usdt.mint(address(this), 1000e6);
        dai.approve(address(pool), type(uint256).max);
        usdt.approve(address(pool), type(uint256).max);

        pool.supply(20e18, 1000e6);
        assertEq(dai.balanceOf(address(pool)), 20e18);
        assertEq(usdt.balanceOf(address(pool)), 1000e6);
        assertEq(pool.reserveDai(), 20e18);
        assertEq(pool.reserveUsdt(), 1000e6);

        vm.expectRevert(TwapPool.Price.selector);
        pool.supply(1e18, 1e6);
    }
}
