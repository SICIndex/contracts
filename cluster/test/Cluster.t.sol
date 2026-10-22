// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ManualOracle} from "../src/ManualOracle.sol";
import {SiciCluster} from "../src/SiciCluster.sol";
import {SiciEVC} from "../src/SiciEVC.sol";
import {SiciVault} from "../src/SiciVault.sol";
import {MockERC20} from "./Mocks.sol";

contract ClusterTest is Test {
    ManualOracle internal oracle;
    SiciEVC internal evc;
    SiciCluster internal cluster;
    MockERC20 internal token;
    SiciVault internal vault;

    address internal governor = address(this);
    address internal user = address(0xA11CE);
    address internal agent = address(0xA9E17);

    uint256 internal constant UNIT = 1e18;
    uint256 internal constant ONE = 1e18;

    function setUp() public {
        oracle = new ManualOracle(governor);
        evc = new SiciEVC();
        cluster = new SiciCluster(address(oracle), governor);
        token = new MockERC20("Livepeer", "LPT", 18);
        vault = new SiciVault(address(evc), address(cluster), address(token), "SICI LPT", "sLPT");
        oracle.setPrice(address(token), ONE);
        cluster.addVault(address(vault), 4000);
        token.mint(user, 1_000 * UNIT);
    }

    function testSupplyAndBorrowAreOn() public view {
        assertTrue(vault.supplyEnabled());
        assertTrue(vault.borrowEnabled());
    }

    function testOperatorBorrowsWithinLtvAndNotAbove() public {
        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(1_000 * UNIT, user);
        evc.setAccountOperator(user, agent, true);
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(SiciVault.borrow.selector, 400 * UNIT, agent);
        vm.prank(agent);
        evc.call(address(vault), user, 0, data);
        assertEq(vault.borrows(user), 400 * UNIT);
        assertEq(token.balanceOf(agent), 400 * UNIT);

        bytes memory tooMuch = abi.encodeWithSelector(SiciVault.borrow.selector, 1, agent);
        vm.prank(agent);
        vm.expectRevert(SiciVault.Insolvent.selector);
        evc.call(address(vault), user, 0, tooMuch);
    }

    function testStrangerCannotBorrowForTheUser() public {
        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(1_000 * UNIT, user);
        vm.stopPrank();

        bytes memory data = abi.encodeWithSelector(SiciVault.borrow.selector, 1 * UNIT, agent);
        vm.prank(agent);
        vm.expectRevert(SiciEVC.NotAuthorized.selector);
        evc.call(address(vault), user, 0, data);
    }

    function testRepayThenWithdraw() public {
        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(1_000 * UNIT, user);
        evc.setAccountOperator(user, agent, true);
        vm.stopPrank();

        vm.prank(agent);
        evc.call(address(vault), user, 0, abi.encodeWithSelector(SiciVault.borrow.selector, 100 * UNIT, agent));

        vm.startPrank(agent);
        token.approve(address(vault), type(uint256).max);
        vault.repay(100 * UNIT, user);
        vm.stopPrank();
        assertEq(vault.borrows(user), 0);

        vm.prank(user);
        vault.withdraw(1_000 * UNIT, user, user);
        assertEq(vault.balanceOf(user), 0);
        assertEq(token.balanceOf(user), 1_000 * UNIT);
    }

    function testGovernorCanAddAnotherMarket() public {
        MockERC20 next = new MockERC20("Trace", "TRAC", 18);
        SiciVault nextVault = new SiciVault(address(evc), address(cluster), address(next), "SICI TRAC", "sTRAC");
        cluster.addVault(address(nextVault), 5000);
        assertEq(cluster.vaultCount(), 2);
        assertEq(cluster.ltvBps(address(nextVault)), 5000);
        assertTrue(nextVault.supplyEnabled());
        assertTrue(nextVault.borrowEnabled());
    }
}
