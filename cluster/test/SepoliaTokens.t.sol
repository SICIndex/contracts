// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TestERC20} from "../src/TestERC20.sol";
import {ProviderPayee} from "../src/ProviderPayee.sol";

contract SepoliaTokensTest is Test {
    function test_usdt_is_six_decimals_and_minted() public {
        TestERC20 usdt = new TestERC20("USDT", "USDT", 6, 1_000_000e6);
        assertEq(usdt.decimals(), 6);
        assertEq(usdt.balanceOf(address(this)), 1_000_000e6);
    }

    function test_payee_pulls_the_approved_remainder() public {
        TestERC20 usdt = new TestERC20("USDT", "USDT", 6, 0);
        ProviderPayee payee = new ProviderPayee();
        address payer = address(0xB0B);
        usdt.mint(payer, 100e6);
        vm.startPrank(payer);
        usdt.approve(address(payee), 99_750_000);
        payee.pull(address(usdt), 99_750_000);
        vm.stopPrank();
        assertEq(usdt.balanceOf(address(payee)), 99_750_000);
        assertEq(usdt.balanceOf(payer), 100e6 - 99_750_000);
    }
}
