// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICompexIndex, INotionalWriter} from "./interfaces/ICompex.sol";
import {IPriceSource, IPushDai} from "./interfaces/IPriceSource.sol";
import {Constituents} from "./libraries/Constituents.sol";
import {FullMath} from "./libraries/FullMath.sol";

/// @notice Usage-weighted compute index. Does not hold tokens.
/// @dev Weights are basis points of enabled fee notionals and sum to 10000.
///      The remainder goes to the enabled constituent with the largest notional.
///      Ties keep the earliest id in DAI, TRAC, RENDER, LPT, IRYS, AKT, RITUAL.
contract CompexIndex is ICompexIndex, INotionalWriter {
    uint256 internal constant BPS = 10_000;
    uint256 internal constant START = 100e18;

    address public admin;
    address public notionalWriter;
    IPriceSource public prices;

    uint256 private level_;
    uint64 private updatedAt_;
    bool private initialized_;

    mapping(bytes32 => bool) private enabled_;
    mapping(bytes32 => uint256) private notional_;
    mapping(bytes32 => uint16) private weight_;
    mapping(bytes32 => uint256) private prevUsd_;
    /// @dev Prices read during the current rebalance. Not a published oracle.
    mapping(bytes32 => uint256) private spotUsd_;

    constructor(address admin_, IPriceSource prices_) {
        require(admin_ != address(0) && address(prices_) != address(0), "zero");
        admin = admin_;
        prices = prices_;
        bytes32[7] memory ids = Constituents.all();
        for (uint256 i; i < ids.length; i++) {
            if (ids[i] != Constituents.RITUAL) enabled_[ids[i]] = true;
        }
    }

    function setNotionalWriter(address writer) external {
        require(msg.sender == admin, "admin");
        require(notionalWriter == address(0), "once");
        require(writer != address(0), "zero");
        notionalWriter = writer;
    }

    function setPriceSource(IPriceSource next) external {
        require(msg.sender == admin, "admin");
        require(address(next) != address(0), "zero");
        prices = next;
    }

    function setEnabled(bytes32 constituent, bool on) external {
        require(msg.sender == admin, "admin");
        require(Constituents.isKnown(constituent), "constituent");
        enabled_[constituent] = on;
        emit ConstituentToggled(constituent, on);
    }

    /// @notice Push AKT or RITUAL and rebalance in this transaction. `daiPerWholeToken` is 1e18-scaled DAI.
    function pushAndRebalance(bytes32[] calldata ids, uint256[] calldata daiPerWholeToken) external {
        require(msg.sender == admin, "admin");
        require(ids.length == daiPerWholeToken.length, "len");
        for (uint256 i; i < ids.length; i++) {
            IPushDai(address(prices)).pushDaiPerToken(ids[i], daiPerWholeToken[i]);
        }
        rebalance();
    }

    function addNotional(bytes32 constituent, uint256 notionalDai) external {
        require(msg.sender == notionalWriter, "writer");
        require(Constituents.isKnown(constituent), "constituent");
        notional_[constituent] += notionalDai;
    }

    function viewIndex() external view returns (uint256 level, uint64 updatedAt, bool initialized) {
        return (level_, updatedAt_, initialized_);
    }

    function weightBps(bytes32 constituent) external view returns (uint16) {
        return weight_[constituent];
    }

    function feeNotionalDai(bytes32 constituent) external view returns (uint256) {
        return notional_[constituent];
    }

    function enabled(bytes32 constituent) external view returns (bool) {
        return enabled_[constituent];
    }

    function rebalance() public {
        _writeWeights();
        (uint256 numer, uint256 denom) = _loadPrices();
        if (!initialized_) {
            level_ = START;
            initialized_ = true;
        } else {
            level_ = FullMath.mulDiv(level_, numer, denom);
        }
        _storePrices();
        updatedAt_ = uint64(block.timestamp);
        emit IndexUpdated(level_, updatedAt_);
    }

    function _writeWeights() internal {
        bytes32[7] memory ids = Constituents.all();
        uint256 total = _enabledTotal(ids);
        require(total > 0, "no fee");

        uint256 assigned;
        uint256 maxNotional;
        uint256 maxIndex;
        bool haveMax;
        for (uint256 i; i < ids.length; i++) {
            bytes32 id = ids[i];
            if (!enabled_[id]) {
                weight_[id] = 0;
                continue;
            }
            uint256 n = notional_[id];
            uint256 w = n * BPS / total;
            weight_[id] = uint16(w);
            assigned += w;
            if (!haveMax || n > maxNotional) {
                maxNotional = n;
                maxIndex = i;
                haveMax = true;
            }
        }
        uint256 leftover = BPS - assigned;
        bytes32 winner = ids[maxIndex];
        weight_[winner] = uint16(uint256(weight_[winner]) + leftover);
    }

    function _enabledTotal(bytes32[7] memory ids) internal view returns (uint256 total) {
        for (uint256 i; i < ids.length; i++) {
            if (enabled_[ids[i]]) total += notional_[ids[i]];
        }
    }

    function _loadPrices() internal returns (uint256 numer, uint256 denom) {
        bytes32[7] memory ids = Constituents.all();
        for (uint256 i; i < ids.length; i++) {
            bytes32 id = ids[i];
            if (!enabled_[id]) continue;
            (uint256 p, bool ok) = prices.usdPrice(id);
            require(ok && p > 0, "missing price");
            spotUsd_[id] = p;
            uint256 w = weight_[id];
            if (w == 0) continue;
            numer += w * p;
            uint256 prev = prevUsd_[id];
            if (prev == 0) prev = p;
            denom += w * prev;
        }
        require(denom > 0, "denom");
    }

    function _storePrices() internal {
        bytes32[7] memory ids = Constituents.all();
        for (uint256 i; i < ids.length; i++) {
            bytes32 id = ids[i];
            if (!enabled_[id]) continue;
            prevUsd_[id] = spotUsd_[id];
        }
    }
}
