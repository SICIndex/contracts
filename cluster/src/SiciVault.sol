// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISiciCluster, ISiciEVC} from "./interfaces/ISici.sol";

/// @notice One ERC-4626 style market. Supply and borrow are both on unless the governor turns one off.
/// A user deposits with their own wallet. An operator, acting through the EVC, borrows against that deposit.
///
/// Interest: a kinked utilization curve (`_borrowRateBps`), same shape Compound/Aave/Euler use. Below
/// `kinkBps` utilization the borrow APR rises slowly (`slope1Bps`); above it, steeply (`slope2Bps`) --
/// that steep slope is what pushes utilization back down before the vault runs dry of liquidity.
/// Accrued interest is added to `totalBorrows` only; no supplier balance is ever rewritten. Since
/// `convertToAssets` divides `totalAssets()` (= `_balance(asset) + totalBorrows`) by `totalSupply`,
/// growing `totalBorrows` alone makes every existing share worth more -- the same mechanism cTokens/
/// aTokens use. Individual borrowers are tracked by a borrow index (`borrowIndex`, Compound's pattern):
/// each account stores a principal and the index value at its last interaction, so interest accrues per
/// account proportional to its share of total debt without a loop over every borrower.
contract SiciVault {
    address public immutable evc;
    address public immutable cluster;
    address public immutable asset;
    address public governor;

    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    uint256 public totalBorrows;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) private principal;
    mapping(address => uint256) private accountIndex;

    bool public supplyEnabled = true;
    bool public borrowEnabled = true;

    /// @dev 1e18-scaled cumulative interest multiplier. Starts at 1.0.
    uint256 public borrowIndex = 1e18;
    uint256 public lastAccrualTs;

    uint256 private constant BPS = 10_000;
    uint256 private constant YEAR = 365 days;

    /// @dev Borrow APR (bps) at 0% and at the kink, and the APR added per bps past the kink up to 100%.
    uint256 public baseRateBps;
    uint256 public slope1Bps;
    uint256 public slope2Bps;
    uint256 public kinkBps;

    uint256 private locked;

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, address indexed owner, address indexed receiver, uint256 assets);
    event Borrow(address indexed account, address indexed receiver, uint256 assets);
    event Repay(address indexed payer, address indexed account, uint256 assets);
    event Transfer(address indexed from, address indexed to, uint256 shares);
    event MarketFlag(bool supplyEnabled, bool borrowEnabled);
    event RateModelSet(uint256 baseRateBps, uint256 slope1Bps, uint256 slope2Bps, uint256 kinkBps);
    event Accrue(uint256 totalBorrows, uint256 borrowIndex);

    error NotGovernor();
    error ZeroAddress();
    error Closed();
    error NotListed();
    error Insolvent();
    error NotAllowed();
    error Reentrancy();
    error TransferFailed();
    error BadRateModel();

    modifier nonReentrant() {
        if (locked != 0) revert Reentrancy();
        locked = 1;
        _;
        locked = 0;
    }

    constructor(address evc_, address cluster_, address asset_, string memory name_, string memory symbol_) {
        if (evc_ == address(0) || cluster_ == address(0) || asset_ == address(0)) revert ZeroAddress();
        evc = evc_;
        cluster = cluster_;
        asset = asset_;
        name = name_;
        symbol = symbol_;
        decimals = _decimals(asset_);
        governor = msg.sender;
        lastAccrualTs = block.timestamp;
        // Defaults: 0% at 0% utilization, 10% APR at the 80% kink, 310% APR at 100% utilization.
        kinkBps = 8_000;
        slope1Bps = 1_000;
        slope2Bps = 30_000;
    }

    function setGovernor(address next) external {
        if (msg.sender != governor) revert NotGovernor();
        if (next == address(0)) revert ZeroAddress();
        governor = next;
    }

    function setEnabled(bool supplyOn, bool borrowOn) external {
        if (msg.sender != governor) revert NotGovernor();
        supplyEnabled = supplyOn;
        borrowEnabled = borrowOn;
        emit MarketFlag(supplyOn, borrowOn);
    }

    /// @notice Accrues under the old curve before switching, so a rate change never applies retroactively.
    function setRateModel(uint256 baseBps, uint256 slope1, uint256 slope2, uint256 kink) external {
        if (msg.sender != governor) revert NotGovernor();
        if (kink > BPS) revert BadRateModel();
        _accrue();
        baseRateBps = baseBps;
        slope1Bps = slope1;
        slope2Bps = slope2;
        kinkBps = kink;
        emit RateModelSet(baseBps, slope1, slope2, kink);
    }

    /// @notice Current borrow APR, in bps, at today's utilization.
    function borrowRateBps() external view returns (uint256) {
        return _borrowRateBps(totalBorrows, totalAssets());
    }

    /// @notice Current supply APR, in bps: the borrow rate earned only on the borrowed share of the pool.
    function supplyRateBps() external view returns (uint256) {
        uint256 assets = totalAssets();
        if (assets == 0) return 0;
        uint256 borrows_ = totalBorrows;
        return (_borrowRateBps(borrows_, assets) * borrows_) / assets;
    }

    function totalAssets() public view returns (uint256) {
        return _balance(asset) + _pendingTotalBorrows();
    }

    function accountAssets(address account) public view returns (uint256) {
        return convertToAssets(balanceOf[account]);
    }

    /// @notice Live debt, including interest accrued since the last transaction touched this vault.
    /// Same name and signature as the old `public mapping(address => uint256) borrows` it replaces --
    /// every existing caller (SiciCluster.solvent, this app's vault.ts) keeps working unchanged.
    function borrows(address account) public view returns (uint256) {
        uint256 idx = accountIndex[account];
        if (idx == 0) return 0;
        return (principal[account] * _pendingBorrowIndex()) / idx;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        uint256 assetsIn = totalAssets();
        if (supply == 0 || assetsIn == 0) return assets;
        return assets * supply / assetsIn;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return shares;
        return shares * totalAssets() / supply;
    }

    function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 shares) {
        if (!supplyEnabled) revert Closed();
        if (receiver == address(0)) revert ZeroAddress();
        if (assets == 0) revert TransferFailed();
        _accrue();
        shares = convertToShares(assets);
        if (shares == 0) revert TransferFailed();
        _pull(msg.sender, assets);
        totalSupply += shares;
        balanceOf[receiver] += shares;
        emit Transfer(address(0), receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner_) external nonReentrant returns (uint256 shares) {
        if (!supplyEnabled) revert Closed();
        if (receiver == address(0)) revert ZeroAddress();
        _accrue();
        address account = _acting(owner_);
        shares = convertToShares(assets);
        balanceOf[account] -= shares;
        totalSupply -= shares;
        if (ISiciCluster(cluster).listed(address(this)) && !ISiciCluster(cluster).solvent(account)) revert Insolvent();
        _push(receiver, assets);
        emit Transfer(account, address(0), shares);
        emit Withdraw(msg.sender, account, receiver, assets);
    }

    /// @notice Borrow `assets` against the acting account. Through the EVC, the account is the collateral owner.
    function borrow(uint256 assets, address receiver) external nonReentrant returns (uint256) {
        if (!borrowEnabled) revert Closed();
        if (!ISiciCluster(cluster).listed(address(this))) revert NotListed();
        if (receiver == address(0)) revert ZeroAddress();
        if (assets == 0) revert TransferFailed();
        _accrue();
        address account = _borrower();
        uint256 owed = _settle(account) + assets;
        principal[account] = owed;
        accountIndex[account] = borrowIndex;
        totalBorrows += assets;
        if (!ISiciCluster(cluster).solvent(account)) revert Insolvent();
        _push(receiver, assets);
        emit Borrow(account, receiver, assets);
        return assets;
    }

    /// @notice Repay `onBehalfOf`. Pulls tokens from the caller. Caps at the outstanding debt.
    function repay(uint256 assets, address onBehalfOf) external nonReentrant returns (uint256 paid) {
        if (onBehalfOf == address(0)) revert ZeroAddress();
        _accrue();
        uint256 owed = _settle(onBehalfOf);
        paid = assets > owed ? owed : assets;
        if (paid == 0) return 0;
        _pull(msg.sender, paid);
        uint256 remaining = owed - paid;
        principal[onBehalfOf] = remaining;
        accountIndex[onBehalfOf] = remaining == 0 ? 0 : borrowIndex;
        totalBorrows -= paid;
        emit Repay(msg.sender, onBehalfOf, paid);
    }

    /// @dev Account's live debt as of the last `_accrue()`. Must be called after `_accrue()`, not before --
    /// `borrowIndex` has to already be caught up or this and `totalBorrows` would disagree.
    function _settle(address account) internal view returns (uint256) {
        uint256 idx = accountIndex[account];
        if (idx == 0) return 0;
        return (principal[account] * borrowIndex) / idx;
    }

    /// @dev Adds interest accrued since `lastAccrualTs` to `totalBorrows`, and grows `borrowIndex` by the
    /// same fraction so every account's `_settle` stays proportional to its share of the pool.
    function _accrue() internal {
        uint256 elapsed = block.timestamp - lastAccrualTs;
        if (elapsed == 0) return;
        lastAccrualTs = block.timestamp;
        uint256 borrows_ = totalBorrows;
        if (borrows_ == 0) return;
        uint256 interest = _interest(borrows_, _borrowRateBps(borrows_, _balance(asset) + borrows_), elapsed);
        if (interest == 0) return;
        totalBorrows = borrows_ + interest;
        borrowIndex += (borrowIndex * interest) / borrows_;
        emit Accrue(totalBorrows, borrowIndex);
    }

    /// @dev Read-only version of what `_accrue()` would do, for views between transactions.
    function _pendingTotalBorrows() internal view returns (uint256) {
        uint256 borrows_ = totalBorrows;
        uint256 elapsed = block.timestamp - lastAccrualTs;
        if (elapsed == 0 || borrows_ == 0) return borrows_;
        return borrows_ + _interest(borrows_, _borrowRateBps(borrows_, _balance(asset) + borrows_), elapsed);
    }

    function _pendingBorrowIndex() internal view returns (uint256) {
        uint256 borrows_ = totalBorrows;
        uint256 elapsed = block.timestamp - lastAccrualTs;
        if (elapsed == 0 || borrows_ == 0) return borrowIndex;
        uint256 interest = _interest(borrows_, _borrowRateBps(borrows_, _balance(asset) + borrows_), elapsed);
        if (interest == 0) return borrowIndex;
        return borrowIndex + (borrowIndex * interest) / borrows_;
    }

    function _interest(uint256 borrows_, uint256 rateBps, uint256 elapsed) internal pure returns (uint256) {
        return (borrows_ * rateBps * elapsed) / (BPS * YEAR);
    }

    /// @dev A kinked linear curve: `baseRateBps` at 0% utilization, rising to `baseRateBps + slope1Bps` at
    /// the kink, then rising by up to `slope2Bps` more between the kink and 100%.
    function _borrowRateBps(uint256 borrows_, uint256 assets_) internal view returns (uint256) {
        if (assets_ == 0) return baseRateBps;
        uint256 utilBps = (borrows_ * BPS) / assets_;
        if (utilBps > BPS) utilBps = BPS;
        if (utilBps <= kinkBps) {
            if (kinkBps == 0) return baseRateBps + slope1Bps;
            return baseRateBps + (utilBps * slope1Bps) / kinkBps;
        }
        uint256 excessBps = utilBps - kinkBps;
        uint256 maxExcessBps = BPS - kinkBps;
        return baseRateBps + slope1Bps + (excessBps * slope2Bps) / maxExcessBps;
    }

    function _borrower() internal view returns (address account) {
        if (msg.sender == evc) {
            account = ISiciEVC(evc).onBehalfOfAccount();
            if (account == address(0)) revert NotAllowed();
            return account;
        }
        return msg.sender;
    }

    function _acting(address owner_) internal view returns (address) {
        if (msg.sender == evc) {
            address behalf = ISiciEVC(evc).onBehalfOfAccount();
            if (behalf != owner_) revert NotAllowed();
            return behalf;
        }
        if (msg.sender != owner_) revert NotAllowed();
        return owner_;
    }

    function _pull(address from, uint256 amount) internal {
        (bool ok, bytes memory data) = asset.call(abi.encodeWithSelector(0x23b872dd, from, address(this), amount));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }

    function _push(address to, uint256 amount) internal {
        (bool ok, bytes memory data) = asset.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }

    function _balance(address token) internal view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(0x70a08231, address(this)));
        if (!ok || data.length < 32) return 0;
        return abi.decode(data, (uint256));
    }

    function _decimals(address token) internal view returns (uint8) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(0x313ce567));
        if (!ok || data.length < 32) return 18;
        return abi.decode(data, (uint8));
    }
}
