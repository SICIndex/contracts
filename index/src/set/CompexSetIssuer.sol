// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICompexIndex} from "../interfaces/ICompex.sol";
import {IPriceSource} from "../interfaces/IPriceSource.sol";
import {TokenLib} from "../libraries/TokenLib.sol";
import {BasicIssuanceModule} from "./BasicIssuanceModule.sol";
import {ConstituentDesk} from "./ConstituentDesk.sol";
import {ISetToken} from "./ISetToken.sol";
import {PreciseUnitMath} from "./PreciseUnitMath.sol";

/// @notice Buys the set with one USDT payment.
///         Position units follow `CompexIndex` fee weights. The desk purchase is a real token transfer
///         into the set, and the buyer receives the set shares.
contract CompexSetIssuer {
    uint256 internal constant BPS = 10_000;

    address public admin;
    ISetToken public setToken;
    BasicIssuanceModule public issuance;
    ConstituentDesk public desk;
    ICompexIndex public index;
    IPriceSource public prices;
    address public usdt;
    uint8 public usdtDecimals;

    bytes32[] public ids;
    address[] public tokens;
    uint8[] public decimals_;
    mapping(address => bytes32) public idOf;

    bool public synced;
    uint256 private locked;

    event Synced(uint256 level);
    event Purchased(address indexed buyer, uint256 shares, uint256 usdtPaid, uint256 indexLevel);

    error NotAdmin();
    error Locked();

    modifier lock() {
        if (locked != 0) revert Locked();
        locked = 1;
        _;
        locked = 0;
    }

    constructor(
        address admin_,
        ISetToken setToken_,
        BasicIssuanceModule issuance_,
        ConstituentDesk desk_,
        ICompexIndex index_,
        IPriceSource prices_,
        address usdt_,
        uint8 usdtDecimals_,
        bytes32[] memory ids_,
        address[] memory tokens_,
        uint8[] memory decimalsIn
    ) {
        require(admin_ != address(0) && address(setToken_) != address(0), "zero");
        require(address(issuance_) != address(0) && address(desk_) != address(0), "zero");
        require(address(index_) != address(0) && address(prices_) != address(0) && usdt_ != address(0), "zero");
        require(ids_.length == tokens_.length && ids_.length == decimalsIn.length && ids_.length > 0, "len");
        admin = admin_;
        setToken = setToken_;
        issuance = issuance_;
        desk = desk_;
        index = index_;
        prices = prices_;
        usdt = usdt_;
        usdtDecimals = usdtDecimals_;
        for (uint256 i; i < ids_.length; i++) {
            require(tokens_[i] != address(0) && idOf[tokens_[i]] == bytes32(0), "token");
            ids.push(ids_[i]);
            tokens.push(tokens_[i]);
            decimals_.push(decimalsIn[i]);
            idOf[tokens_[i]] = ids_[i];
        }
    }

    /// @notice Register this contract as a set module. The manager initializes issuance separately.
    function register() external {
        if (msg.sender != admin) revert NotAdmin();
        setToken.initializeModule();
    }

    /// @notice Rewrite the set's positions to the current fee weights.
    ///         With no supply, this only stores units. With supply, the set trades with the desk.
    function sync() external lock {
        (uint256 level,, bool init) = index.viewIndex();
        require(init && level > 0, "index");
        uint256 supply = setToken.totalSupply();
        uint256[] memory targets = new uint256[](ids.length);
        for (uint256 i; i < ids.length; i++) {
            uint256 weight = index.weightBps(ids[i]);
            address token = tokens[i];
            if (weight == 0) {
                targets[i] = 0;
                continue;
            }
            (uint256 price, bool ok) = prices.usdPrice(ids[i]);
            require(ok && price > 0, "price");
            uint256 unit = _unit(level, weight, decimals_[i], price);
            require(unit > 0, "unit");
            if (!setToken.isComponent(token)) setToken.addComponent(token);
            setToken.editDefaultPositionUnit(token, int256(unit));
            targets[i] = supply == 0 ? 0 : PreciseUnitMath.preciseMulCeil(unit, supply);
        }
        if (supply > 0) {
            for (uint256 i; i < ids.length; i++) {
                if (!setToken.isComponent(tokens[i])) continue;
                uint256 current = TokenLib.balanceOf(tokens[i], address(setToken));
                if (current > targets[i]) _sell(tokens[i], current - targets[i]);
            }
            for (uint256 i; i < ids.length; i++) {
                if (!setToken.isComponent(tokens[i])) continue;
                uint256 current = TokenLib.balanceOf(tokens[i], address(setToken));
                if (targets[i] > current) _buy(tokens[i], targets[i] - current);
            }
            for (uint256 i; i < ids.length; i++) {
                if (targets[i] == 0 && setToken.isComponent(tokens[i])) {
                    setToken.editDefaultPositionUnit(tokens[i], 0);
                    setToken.removeComponent(tokens[i]);
                }
            }
        }
        synced = true;
        emit Synced(level);
    }

    /// @notice Shares and USDT cost for spending at most `maxUsdt`.
    function quoteBuy(uint256 maxUsdt) external view returns (uint256 shares, uint256 cost) {
        (uint256 level,, bool init) = index.viewIndex();
        require(init && level > 0 && synced, "index");
        shares = _sharesFor(maxUsdt, level);
        cost = _cost(shares);
        if (cost > maxUsdt && cost > 0) {
            shares = shares * maxUsdt / cost;
            cost = _cost(shares);
        }
    }

    /// @notice One payment. Pulls USDT, buys the fee-weighted tokens, and mints shares to the caller.
    function buyForUsdt(uint256 maxUsdt, uint256 minShares) external lock returns (uint256 shares) {
        require(synced, "sync");
        (uint256 level,, bool init) = index.viewIndex();
        require(init && level > 0, "index");
        (shares,) = this.quoteBuy(maxUsdt);
        require(shares >= minShares && shares > 0, "shares");
        (address[] memory components, uint256[] memory amounts) = issuance.getRequiredComponentIssuanceUnits(setToken, shares);
        uint256 cost;
        uint256[] memory paid = new uint256[](components.length);
        for (uint256 i; i < components.length; i++) {
            paid[i] = desk.quote(components[i], amounts[i]);
            cost += paid[i];
        }
        require(cost > 0 && cost <= maxUsdt, "cost");
        TokenLib.safeTransferFrom(usdt, msg.sender, address(this), cost);
        TokenLib.safeApprove(usdt, address(desk), cost);
        for (uint256 i; i < components.length; i++) {
            desk.buy(components[i], amounts[i]);
            TokenLib.safeApprove(components[i], address(issuance), amounts[i]);
        }
        TokenLib.safeApprove(usdt, address(desk), 0);
        issuance.issue(setToken, shares, msg.sender);
        emit Purchased(msg.sender, shares, cost, level);
    }

    /// @notice USD value of one share, 1e18 scale. Before the first fee this is not priced.
    function sharePrice() external view returns (uint256 usdPerShare, bool ok) {
        (uint256 level,, bool init) = index.viewIndex();
        if (!init || !synced) return (0, false);
        uint256 supply = setToken.totalSupply();
        if (supply == 0) return (level, true);
        uint256 nav;
        for (uint256 i; i < tokens.length; i++) {
            if (!setToken.isComponent(tokens[i])) continue;
            (uint256 price, bool priced) = prices.usdPrice(ids[i]);
            if (!priced || price == 0) return (0, false);
            uint256 bal = TokenLib.balanceOf(tokens[i], address(setToken));
            nav += bal * price / (10 ** uint256(decimals_[i]));
        }
        return (nav * 1e18 / supply, true);
    }

    function _sharesFor(uint256 maxUsdt, uint256 level) internal view returns (uint256) {
        uint256 usd = maxUsdt * (10 ** (18 - uint256(usdtDecimals)));
        return usd * 1e18 / level;
    }

    function _unit(uint256 level, uint256 weight, uint8 dec, uint256 price) internal pure returns (uint256) {
        return level * weight * (10 ** uint256(dec)) / (BPS * price);
    }

    function _cost(uint256 shares) internal view returns (uint256 cost) {
        if (shares == 0) return 0;
        (address[] memory components, uint256[] memory amounts) =
            issuance.getRequiredComponentIssuanceUnits(setToken, shares);
        for (uint256 i; i < components.length; i++) {
            cost += desk.quote(components[i], amounts[i]);
        }
    }

    function _sell(address token, uint256 amount) internal {
        uint256 usdtOut = desk.quote(token, amount);
        if (usdtOut == 0) return;
        setToken.invoke(token, 0, abi.encodeWithSignature("approve(address,uint256)", address(desk), amount));
        setToken.invoke(address(desk), 0, abi.encodeWithSignature("sell(address,uint256)", token, amount));
    }

    function _buy(address token, uint256 amount) internal {
        uint256 usdtCost = desk.quote(token, amount);
        if (usdtCost == 0) return;
        setToken.invoke(usdt, 0, abi.encodeWithSignature("approve(address,uint256)", address(desk), usdtCost));
        setToken.invoke(address(desk), 0, abi.encodeWithSignature("buy(address,uint256)", token, amount));
    }
}
