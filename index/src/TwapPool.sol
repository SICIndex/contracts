// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice DAI/USDT pool with a Uniswap V3 `observe` surface.
///         Liquidity is the tokens supplied here, at a fixed 1 DAI = 50 USDT.
///         The tick is constant, so a 30-minute TWAP is readable in the same block
///         the pool is created. A canonical V3 pool cannot answer that window until
///         it has been alive for 30 minutes.
contract TwapPool {
    uint256 internal constant DAI_DECIMALS = 18;
    uint256 internal constant DAI_PER_USDT = 50;
    uint32 internal constant TWAP_SECONDS = 1800;

    address public immutable dai;
    address public immutable usdt;
    uint8 public immutable usdtDecimals;
    int24 public immutable tick;

    address public immutable token0;
    address public immutable token1;

    uint256 public reserveDai;
    uint256 public reserveUsdt;

    error BadPair();
    error BadTick();
    error Price();
    error TransferFailed();

    constructor(address dai_, address usdt_, uint8 usdtDecimals_, int24 tick_) {
        if (dai_ == address(0) || usdt_ == address(0) || dai_ == usdt_) revert BadPair();
        if (usdtDecimals_ > 18) revert BadPair();
        if (tick_ > 887272 || tick_ < -887272) revert BadTick();
        dai = dai_;
        usdt = usdt_;
        usdtDecimals = usdtDecimals_;
        tick = tick_;
        if (dai_ < usdt_) {
            token0 = dai_;
            token1 = usdt_;
        } else {
            token0 = usdt_;
            token1 = dai_;
        }
    }

    /// @notice Pull DAI and USDT at exactly 1 whole DAI = 50 whole USDT.
    function supply(uint256 daiAmount, uint256 usdtAmount) external {
        uint256 unit = 10 ** uint256(usdtDecimals);
        if (daiAmount == 0 || usdtAmount == 0) revert Price();
        if (usdtAmount * (10 ** DAI_DECIMALS) != daiAmount * DAI_PER_USDT * unit) revert Price();
        _pull(dai, daiAmount);
        _pull(usdt, usdtAmount);
        reserveDai += daiAmount;
        reserveUsdt += usdtAmount;
    }

    /// @notice Constant-tick cumulatives. `secondsAgos` of [1800, 0] is the window
    ///         `UniPriceSource` requests, and any shorter window returns the same tick.
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory cumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        cumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        int56 nowCum = int56(tick) * int56(uint56(TWAP_SECONDS));
        for (uint256 i; i < secondsAgos.length; i++) {
            cumulatives[i] = nowCum - int56(tick) * int56(uint56(secondsAgos[i]));
        }
    }

    function _pull(address token, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, msg.sender, address(this), amount)
        );
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }
}
