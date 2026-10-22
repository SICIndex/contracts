// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FullMath} from "./FullMath.sol";

/// @notice 1.0001^tick as a Uniswap-style price, without vendoring Uniswap.
/// @dev `sqrtRatio` is sqrt(1.0001^tick) in Q128.128. Bit factors are rounded
///      from decimal 1.0001^(2^(i-1)), not copied from another tree.
library PriceMath {
    uint256 internal constant Q128 = 1 << 128;
    int24 internal constant MAX_TICK = 887272;
    /// @dev Thirty minutes. The V3 adapter asks the pool for this window.
    uint32 internal constant TWAP_SECONDS = 1800;

    // sqrt(1.0001^(2^i)) in Q128.128, i = 0..19.
    uint256 private constant S0 = 340299380613952818054172298683778356828;
    uint256 private constant S1 = 340316395157630557309720944892511388277;
    uint256 private constant S2 = 340350426797146320365451916987000639416;
    uint256 private constant S3 = 340418500286010017600988211024917209414;
    uint256 private constant S4 = 340554688112596146811623731040025550736;
    uint256 private constant S5 = 340827227237472341863836470820749023631;
    uint256 private constant S6 = 341372959984650275276033597306520743141;
    uint256 private constant S7 = 342467048360920826462928722886081615600;
    uint256 private constant S8 = 344665755896458450296233727269387403731;
    uint256 private constant S9 = 349105610033792638280984123280190328436;
    uint256 private constant S10 = 358157632615101069751276996057946695659;
    uint256 private constant S11 = 376971898253716117623529192837680025079;
    uint256 private constant S12 = 417617325748846587604282738883252442194;
    uint256 private constant S13 = 512527970061227098179808991519084180754;
    uint256 private constant S14 = 771961599044932501159214767853730668404;
    uint256 private constant S15 = 1751265326476546048830215005295408735410;
    uint256 private constant S16 = 9012897939644274835729218063218412887976;
    uint256 private constant S17 = 238720360403857226300850011143463043697824;
    uint256 private constant S18 = 167470947692649603307852627475141582849110686;
    uint256 private constant S19 = 82421309616641213947171380309905481222424097915896;

    /// @notice How many raw `quote` units equal `baseAmount` raw `base` units at `tick`.
    ///         Tick is the pool tick: price of token1 in token0, raw, as 1.0001^tick.
    function quoteRaw(int24 tick, address token0, address base, uint256 baseAmount)
        internal
        pure
        returns (uint256 quoteAmount)
    {
        uint256 s = sqrtRatio(tick);
        if (base == token0) {
            uint256 mid = FullMath.mulDiv(baseAmount, s, Q128);
            quoteAmount = FullMath.mulDiv(mid, s, Q128);
        } else {
            uint256 mid = FullMath.mulDiv(baseAmount, Q128, s);
            quoteAmount = FullMath.mulDiv(mid, Q128, s);
        }
    }

    function sqrtRatio(int24 tick) internal pure returns (uint256) {
        int256 t = int256(tick);
        uint256 n = t < 0 ? uint256(-t) : uint256(t);
        require(n <= uint256(int256(MAX_TICK)), "tick");
        uint256 s = _powSqrt(n);
        if (t < 0) s = FullMath.mulDiv(Q128, Q128, s);
        return s;
    }

    function meanTick(int56 cumulativeThen, int56 cumulativeNow) internal pure returns (int24) {
        int56 delta = cumulativeNow - cumulativeThen;
        int56 dt = int56(uint56(TWAP_SECONDS));
        int56 compressed = delta / dt;
        if (delta < 0 && delta % dt != 0) compressed--;
        require(compressed <= type(int24).max && compressed >= type(int24).min, "tick range");
        return int24(compressed);
    }

    function _powSqrt(uint256 n) private pure returns (uint256 s) {
        s = Q128;
        if (n & 0x1 != 0) s = FullMath.mulDiv(s, S0, Q128);
        if (n & 0x2 != 0) s = FullMath.mulDiv(s, S1, Q128);
        if (n & 0x4 != 0) s = FullMath.mulDiv(s, S2, Q128);
        if (n & 0x8 != 0) s = FullMath.mulDiv(s, S3, Q128);
        if (n & 0x10 != 0) s = FullMath.mulDiv(s, S4, Q128);
        if (n & 0x20 != 0) s = FullMath.mulDiv(s, S5, Q128);
        if (n & 0x40 != 0) s = FullMath.mulDiv(s, S6, Q128);
        if (n & 0x80 != 0) s = FullMath.mulDiv(s, S7, Q128);
        if (n & 0x100 != 0) s = FullMath.mulDiv(s, S8, Q128);
        if (n & 0x200 != 0) s = FullMath.mulDiv(s, S9, Q128);
        if (n & 0x400 != 0) s = FullMath.mulDiv(s, S10, Q128);
        if (n & 0x800 != 0) s = FullMath.mulDiv(s, S11, Q128);
        if (n & 0x1000 != 0) s = FullMath.mulDiv(s, S12, Q128);
        if (n & 0x2000 != 0) s = FullMath.mulDiv(s, S13, Q128);
        if (n & 0x4000 != 0) s = FullMath.mulDiv(s, S14, Q128);
        if (n & 0x8000 != 0) s = FullMath.mulDiv(s, S15, Q128);
        if (n & 0x10000 != 0) s = FullMath.mulDiv(s, S16, Q128);
        if (n & 0x20000 != 0) s = FullMath.mulDiv(s, S17, Q128);
        if (n & 0x40000 != 0) s = FullMath.mulDiv(s, S18, Q128);
        if (n & 0x80000 != 0) s = FullMath.mulDiv(s, S19, Q128);
    }
}
