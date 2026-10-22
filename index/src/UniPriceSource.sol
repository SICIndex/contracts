// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceSource, IPushDai} from "./interfaces/IPriceSource.sol";
import {IUniswapV2Pair, IUniswapV3Pool} from "./interfaces/IExternal.sol";
import {Constituents} from "./libraries/Constituents.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {PriceMath} from "./libraries/PriceMath.sol";

/// @notice Prices constituent tokens in USD.
///         Pool constituents are read from a DAI pair (V3 30-minute TWAP, or V2 spot).
///         AKT and RITUAL are a push, in DAI per whole token.
///         DAI itself is priced from a DAI/USDT pool, or from DAI/WETH plus WETH/USDT.
///         Every address is unset until an admin transaction configures it. Nothing here is a mainnet constant.
contract UniPriceSource is IPriceSource, IPushDai {
    struct Pool {
        address pool;
        address token;
        uint8 decimals;
        bool v3;
        bool set;
    }

    address public admin;
    address public index;

    address public dai;
    uint8 public daiDecimals;

    Pool private usdDirect;
    address public usdQuote;
    uint8 public usdQuoteDecimals;

    Pool private daiWeth;
    Pool private wethUsd;
    address public weth;
    uint8 public wethDecimals;
    bool public usdViaWeth;

    mapping(bytes32 => Pool) private pools;
    mapping(bytes32 => uint256) private pushedDaiPerToken;

    constructor(address admin_) {
        require(admin_ != address(0), "admin");
        admin = admin_;
    }

    function setAdmin(address next) external {
        require(msg.sender == admin, "admin");
        require(next != address(0), "zero");
        admin = next;
    }

    function setIndex(address index_) external {
        require(msg.sender == admin, "admin");
        require(index == address(0), "once");
        require(index_ != address(0), "zero");
        index = index_;
    }

    function setDai(address dai_, uint8 decimals_) external {
        require(msg.sender == admin, "admin");
        require(dai_ != address(0) && decimals_ <= 18, "dai");
        dai = dai_;
        daiDecimals = decimals_;
    }

    /// @notice Spot or TWAP pool of a basket token against DAI. `v3` selects the 30-minute TWAP.
    function setConstituentPool(
        bytes32 constituent,
        address token,
        uint8 decimals_,
        address pool,
        bool v3
    ) external {
        require(msg.sender == admin, "admin");
        require(Constituents.isPool(constituent), "pool id");
        require(token != address(0) && pool != address(0) && decimals_ <= 18, "pool");
        pools[constituent] = Pool(pool, token, decimals_, v3, true);
    }

    /// @notice Direct DAI/USD-quote pool. Clears the WETH path.
    function setUsdPoolDirect(address pool, bool v3, address quoteToken, uint8 quoteDecimals) external {
        require(msg.sender == admin, "admin");
        require(pool != address(0) && quoteToken != address(0) && quoteDecimals <= 18, "usd");
        usdDirect = Pool(pool, dai, daiDecimals, v3, true);
        usdQuote = quoteToken;
        usdQuoteDecimals = quoteDecimals;
        usdViaWeth = false;
    }

    /// @notice DAI priced through WETH: DAI/WETH and WETH/USD-quote. Clears the direct pool flag.
    function setUsdPoolViaWeth(
        address daiWethPool,
        bool daiWethV3,
        address weth_,
        uint8 wethDecimals_,
        address wethUsdPool,
        bool wethUsdV3,
        address quoteToken,
        uint8 quoteDecimals
    ) external {
        require(msg.sender == admin, "admin");
        require(
            daiWethPool != address(0) && wethUsdPool != address(0) && weth_ != address(0)
                && quoteToken != address(0),
            "usd"
        );
        require(wethDecimals_ <= 18 && quoteDecimals <= 18, "dec");
        weth = weth_;
        wethDecimals = wethDecimals_;
        usdQuote = quoteToken;
        usdQuoteDecimals = quoteDecimals;
        daiWeth = Pool(daiWethPool, dai, daiDecimals, daiWethV3, true);
        wethUsd = Pool(wethUsdPool, weth_, wethDecimals_, wethUsdV3, true);
        usdViaWeth = true;
    }

    function pushDaiPerToken(bytes32 constituent, uint256 daiPerWholeToken) external {
        require(msg.sender == admin || msg.sender == index, "admin");
        require(Constituents.isPush(constituent), "push");
        require(daiPerWholeToken > 0, "zero");
        pushedDaiPerToken[constituent] = daiPerWholeToken;
    }

    function usdPrice(bytes32 constituent) external view returns (uint256 price, bool ok) {
        (uint256 daiUsd, bool daiOk) = _daiUsd();
        if (!daiOk) return (0, false);

        if (constituent == Constituents.DAI) return (daiUsd, true);

        uint256 daiPerToken;
        bool have;
        if (Constituents.isPush(constituent)) {
            daiPerToken = pushedDaiPerToken[constituent];
            have = daiPerToken > 0;
        } else if (Constituents.isPool(constituent)) {
            (daiPerToken, have) = _quoteInDai(pools[constituent]);
        } else {
            return (0, false);
        }
        if (!have) return (0, false);
        return (FullMath.mulDiv(daiPerToken, daiUsd, 1e18), true);
    }

    function _daiUsd() internal view returns (uint256 price, bool ok) {
        if (dai == address(0)) return (0, false);
        if (usdViaWeth) {
            if (!daiWeth.set || !wethUsd.set || weth == address(0)) return (0, false);
            Pool memory leg0 = daiWeth;
            leg0.token = dai;
            leg0.decimals = daiDecimals;
            Pool memory leg1 = wethUsd;
            leg1.token = weth;
            leg1.decimals = wethDecimals;
            (uint256 wethPerDai, bool a) = _pairQuote(leg0, weth, wethDecimals);
            (uint256 usdPerWeth, bool b) = _pairQuote(leg1, usdQuote, usdQuoteDecimals);
            if (!a || !b) return (0, false);
            return (FullMath.mulDiv(wethPerDai, usdPerWeth, 1e18), true);
        }
        if (!usdDirect.set || usdQuote == address(0)) return (0, false);
        // The direct pool prices the DAI token. Its stored token/decimals must follow setDai.
        Pool memory direct = usdDirect;
        direct.token = dai;
        direct.decimals = daiDecimals;
        return _pairQuote(direct, usdQuote, usdQuoteDecimals);
    }

    /// @return daiPer 1e18-scaled human DAI for one whole constituent token.
    function _quoteInDai(Pool memory pool) internal view returns (uint256 daiPer, bool ok) {
        if (!pool.set || dai == address(0)) return (0, false);
        return _pairQuote(pool, dai, daiDecimals);
    }

    /// @return scaled 1e18-scaled human `quote` for one whole `pool.token`.
    function _pairQuote(Pool memory pool, address quote, uint8 quoteDecimals)
        internal
        view
        returns (uint256 scaled, bool ok)
    {
        if (!pool.set) return (0, false);
        uint256 raw;
        if (pool.v3) {
            raw = _v3Raw(pool, quote);
        } else {
            raw = _v2Raw(pool, quote);
        }
        if (raw == 0) return (0, false);
        scaled = FullMath.mulDiv(raw, 1e18, 10 ** uint256(quoteDecimals));
        ok = scaled > 0;
    }

    function _v2Raw(Pool memory pool, address quote) internal view returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(pool.pool);
        (uint112 r0, uint112 r1,) = pair.getReserves();
        address t0 = pair.token0();
        address t1 = pair.token1();
        uint256 reserveBase;
        uint256 reserveQuote;
        if (t0 == pool.token && t1 == quote) {
            reserveBase = r0;
            reserveQuote = r1;
        } else if (t1 == pool.token && t0 == quote) {
            reserveBase = r1;
            reserveQuote = r0;
        } else {
            return 0;
        }
        if (reserveBase == 0 || reserveQuote == 0) return 0;
        return FullMath.mulDiv(reserveQuote, 10 ** uint256(pool.decimals), reserveBase);
    }

    function _v3Raw(Pool memory pool, address quote) internal view returns (uint256) {
        IUniswapV3Pool v3 = IUniswapV3Pool(pool.pool);
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = PriceMath.TWAP_SECONDS;
        secondsAgos[1] = 0;
        (int56[] memory cumulatives,) = v3.observe(secondsAgos);
        int24 tick = PriceMath.meanTick(cumulatives[0], cumulatives[1]);
        address t0 = v3.token0();
        address t1 = v3.token1();
        if (!((t0 == pool.token && t1 == quote) || (t1 == pool.token && t0 == quote))) return 0;
        return PriceMath.quoteRaw(tick, t0, pool.token, 10 ** uint256(pool.decimals));
    }
}
