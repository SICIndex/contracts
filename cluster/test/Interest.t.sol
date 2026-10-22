// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ManualOracle} from "../src/ManualOracle.sol";
import {SiciCluster} from "../src/SiciCluster.sol";
import {SiciEVC} from "../src/SiciEVC.sol";
import {SiciVault} from "../src/SiciVault.sol";
import {MockERC20} from "./Mocks.sol";

contract InterestTest is Test {
    ManualOracle internal oracle;
    SiciEVC internal evc;
    SiciCluster internal cluster;
    MockERC20 internal token;
    SiciVault internal vault;

    address internal governor = address(this);
    address internal lender = address(0xBEEF);
    address internal borrower = address(0xB0B);

    uint256 internal constant UNIT = 1e18;

    function setUp() public {
        oracle = new ManualOracle(governor);
        evc = new SiciEVC();
        cluster = new SiciCluster(address(oracle), governor);
        token = new MockERC20("Test", "TST", 18);
        vault = new SiciVault(address(evc), address(cluster), address(token), "SICI TST", "sTST");
        oracle.setPrice(address(token), UNIT);
        cluster.addVault(address(vault), 9_000);
        token.mint(lender, 1_000 * UNIT);
        token.mint(borrower, 2_000 * UNIT); // extra, to repay the accrued interest later
    }

    /// Lender and the borrower's own collateral deposit grow together as debt accrues interest; repaying
    /// the grown debt in real tokens is what lets the lender actually withdraw the grown balance.
    function testInterestAccruesToLenderAndBorrower() public {
        vm.startPrank(lender);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(1_000 * UNIT, lender);
        vm.stopPrank();

        vm.startPrank(borrower);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(1_000 * UNIT, borrower);
        vault.borrow(800 * UNIT, borrower);
        vm.stopPrank();

        uint256 rateBps = vault.borrowRateBps();
        assertGt(rateBps, 0);
        assertEq(vault.borrows(borrower), 800 * UNIT);
        uint256 lenderAssetsBefore = vault.accountAssets(lender);
        assertEq(lenderAssetsBefore, 1_000 * UNIT);

        vm.warp(block.timestamp + 365 days);

        uint256 expectedInterest = (800 * UNIT * rateBps * 365 days) / (10_000 * 365 days);
        assertGt(expectedInterest, 0);
        uint256 debtAfter = vault.borrows(borrower);
        assertEq(debtAfter, 800 * UNIT + expectedInterest);

        // Lender and the borrower's collateral deposit are equal (1,000 each), so the accrued interest
        // splits evenly between their two share balances.
        uint256 lenderAssetsAfter = vault.accountAssets(lender);
        assertApproxEqAbs(lenderAssetsAfter, lenderAssetsBefore + expectedInterest / 2, 2);

        vm.prank(borrower);
        vault.repay(debtAfter, borrower);
        assertEq(vault.borrows(borrower), 0);
        assertEq(vault.totalBorrows(), 0);

        vm.prank(lender);
        vault.withdraw(lenderAssetsAfter, lender, lender);
        assertApproxEqAbs(token.balanceOf(lender), lenderAssetsAfter, 2);
    }

    function testNoInterestWithoutBorrows() public {
        vm.startPrank(lender);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(1_000 * UNIT, lender);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);
        assertEq(vault.accountAssets(lender), 1_000 * UNIT);
        assertEq(vault.totalBorrows(), 0);
    }

    function testRateModelRejectsAKinkAboveOneHundredPercent() public {
        vm.expectRevert(SiciVault.BadRateModel.selector);
        vault.setRateModel(0, 1_000, 30_000, 10_001);
    }

    function testOnlyGovernorSetsTheRateModel() public {
        vm.prank(borrower);
        vm.expectRevert(SiciVault.NotGovernor.selector);
        vault.setRateModel(0, 500, 20_000, 7_000);
    }
}
