// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreasuryToken} from "../src/TreasuryToken.sol";

contract TreasuryTokenTest is Test {
    TreasuryToken token;
    uint256 private initialSupply = 1_000_000 ether;
    address private deployer = makeAddr("deployer");
    address private treasury = makeAddr("treasury");

    function setUp() external {
        vm.prank(deployer);
        token = new TreasuryToken(initialSupply, treasury);
    }

    function test_TreasuryToken_MintsCorrectSupplyToCorrectAddress() external {
        uint256 treasuryMintedAmount = token.balanceOf(treasury);
        assertEq(treasuryMintedAmount, initialSupply, "Initial supply not minted properly");

        // Sanity check: only the treasury holds tokens, no one else got minted to
        address randomAddress = makeAddr("nobody");
        assertEq(token.balanceOf(randomAddress), 0, "Random address received tokens");
    }

    function test_TreasuryToken_NameAndSymbolAreSetCorrectly() external view {
        assertEq(token.name(), "Treasury Token", "Name incorrect");
        assertEq(token.symbol(), "TRES", "Symbol incorrect");
    }

    function test_TreasuryToken_DecimalDefaultsTo18() external view {
        assertEq(token.decimals(), 18, "Decimal not set properly");
    }

    function test_TreasuryToken_TotalAndInitialSupplyAreSame() external view {
        assertEq(token.totalSupply(), initialSupply, "Total supply mismatch");
    }

    function test_TreasuryToken_StandardTransferWorks() external {
        uint256 transferAmount = 5 ether;
        address alice = makeAddr("alice");

        vm.prank(treasury);
        token.transfer(alice, transferAmount);

        assertEq(token.balanceOf(alice), transferAmount, "Transfer is not working properly");
    }

    function test_TreasuryToken_TransferFromAndApproveWorks() external {
        uint256 transferAmount = 5 ether;
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        // Treasury funds Alice
        vm.prank(treasury);
        token.transfer(alice, transferAmount);

        // Alice approves Treasury to spend her tokens
        vm.prank(alice);
        token.approve(treasury, transferAmount);

        uint256 bobBalanceBefore = token.balanceOf(bob);

        // Treasury moves Alice's tokens to Bob
        vm.prank(treasury);
        token.transferFrom(alice, bob, transferAmount);

        uint256 bobBalanceAfter = token.balanceOf(bob);

        assertEq(
            bobBalanceAfter - bobBalanceBefore, transferAmount, "transferFrom and approve is not behaving properly"
        );
    }
}
