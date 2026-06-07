// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MembershipNFT} from "../src/MembershipNFT.sol";

contract MembershipNFTTest is Test {
    // Setup

    MembershipNFT nft;

    address deployer = makeAddr("deployer");
    address minter = makeAddr("minter"); // Will impersonate MerkleClaim
    address governor = makeAddr("governor"); // Will impersonate GovernorContract
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    function setUp() external {
        vm.prank(deployer);
        nft = new MembershipNFT(minter, "Membership", "MEM");

        vm.prank(deployer);
        nft.setGovernor(governor);
    }

    // === Helper Functions ===
    function _deployFreshNft() internal returns (MembershipNFT) {
        vm.prank(deployer);
        return new MembershipNFT(minter, "Fresh", "FR");
    }

    // ==================================
    // ==== Constructor & Setup Tests ===
    // ==================================

    // verify getMinter() returns the minter address
    function test_Constructor_SetsMinter() external view {
        assertEq(nft.getMinter(), minter, "Address of minter not set properly");
    }

    // verify getTokenCounter() returns 0
    function test_Constructor_TokenCounterStartsAtZero() external view {
        assertEq(nft.getTokenCounter(), 0, "Token count is not starting with zero");
    }

    //  deploy fresh NFT, verify getGovernor() == address(0)
    function test_Constructor_GovernorStartsUnset() external {
        MembershipNFT nftNew;
        vm.prank(deployer);
        nftNew = new MembershipNFT(minter, "MembershipNew", "MEMN");

        assertEq(nftNew.getGovernor(), address(0), "Governor address is non-zero");
    }

    // ==================================
    // ====== setGovernor Tests =========
    // ==================================

    // non-deployer reverts
    function test_SetGovernor_OnlyDeployerCanCall() external {
        MembershipNFT nftNew = _deployFreshNft();

        vm.expectRevert(MembershipNFT.MembershipNFT__OnlyDeployer.selector);
        vm.prank(alice);
        nftNew.setGovernor(governor);
    }

    // emits event, getGovernor returns set address
    function test_SetGovernor_SetsCorrectly() external {
        MembershipNFT nftNew = _deployFreshNft();

        vm.expectEmit(true, false, false, false, address(nftNew));
        emit MembershipNFT.GovernorSet(governor);
        vm.prank(deployer);
        nftNew.setGovernor(governor);

        assertEq(nftNew.getGovernor(), governor, "Governor not set properly");
    }

    // second call reverts with GovernorAlreadySet
    function test_SetGovernor_CanOnlyBeCalledOnce() external {
        MembershipNFT nftNew = _deployFreshNft();

        vm.prank(deployer);
        nftNew.setGovernor(governor);

        vm.expectRevert(MembershipNFT.MembershipNFT__GovernorAlreadySet.selector);
        vm.prank(deployer);
        nftNew.setGovernor(makeAddr("differentGovernor"));
    }

    // passing address(0) reverts
    function test_SetGovernor_RevertsOnZeroAddress() external {
        MembershipNFT nftNew = _deployFreshNft();

        vm.expectRevert(MembershipNFT.MembershipNFT__ZeroAddress.selector);
        vm.prank(deployer);
        nftNew.setGovernor(address(0));
    }

    // ==================================
    // ========== mint Tests ============
    // ==================================

    // non-minter reverts
    function test_Mint_OnlyMinterCanCall() external {
        vm.expectRevert(MembershipNFT.MembershipNFT__OnlyMinter.selector);
        vm.prank(alice); // not the minter
        nft.mint(bob, 10);
    }

    // mint three NFTs, verify IDs are 0, 1, 2
    function test_Mint_MintsSequentialTokenIds() external {
        vm.startPrank(minter);
        nft.mint(alice, 5);
        nft.mint(bob, 10);
        nft.mint(charlie, 15);
        vm.stopPrank();

        assertEq(nft.ownerOf(0), alice, "Token 0 should be minted to Alice");
        assertEq(nft.ownerOf(1), bob, "Token 1 should be minted to Bob");
        assertEq(nft.ownerOf(2), charlie, "Token 2 should be minted to Charlie");
    }

    // getVotingPowerOf returns correct value
    function test_Mint_RecordsVotingPower() external {
        vm.prank(minter);
        nft.mint(bob, 10);

        assertEq(nft.getVotingPowerOf(0), 10, "Static voting power should be recorded in NFT");
    }

    // getVotes returns correct value
    function test_Mint_UpdatesUserVotingPower_SingleMint() external {
        vm.prank(minter);
        nft.mint(alice, 10);

        assertEq(nft.getVotes(alice), 10, "getVotes should reflect custom voting power, not NFT count");
    }

    // voting power accumulates
    function test_Mint_UpdatesUserVotingPower_MultipleMintsToSameUser() external {
        vm.prank(minter);
        nft.mint(alice, 10);

        vm.prank(minter);
        nft.mint(alice, 20);

        assertEq(nft.getVotingPowerOf(0), 10, "First token should hold 10 power");
        assertEq(nft.getVotingPowerOf(1), 20, "Second token should hold 20 power");
        assertEq(nft.getVotes(alice), 30, "Total voting power should accumulate to 30");
    }

    // explicitly prove the delegate target is set to the user
    function test_Mint_AutoDelegates() external {
        vm.prank(minter);
        nft.mint(alice, 10);

        // The auto-delegate guarantee: alice is delegated to herself.
        // This proves the delegation explicitly, not just the side effect (nonzero votes).
        assertEq(nft.delegates(alice), alice, "Alice should be auto-delegated to herself");
    }

    // verify that minting to Alice doesn't accidentally give power to Bob
    function test_Mint_DoesNotAffectOtherUsers() external {
        vm.startPrank(minter);
        nft.mint(alice, 10);
        nft.mint(bob, 25);
        vm.stopPrank();

        assertEq(nft.getVotes(alice), 10, "Alice's votes should not include Bob's");
        assertEq(nft.getVotes(bob), 25, "Bob's votes should not include Alice's");
    }

    // verify event with correct params
    function test_Mint_EmitsMintedEvent() external {
        vm.expectEmit(true, true, false, true, address(nft));
        emit MembershipNFT.Minted(alice, 0, 10);
        vm.prank(minter);
        nft.mint(alice, 10);
    }

    function test_Mint_RevertsOnZeroAddress() external {
        vm.expectRevert(MembershipNFT.MembershipNFT__ZeroAddress.selector);
        vm.prank(minter);
        nft.mint(address(0), 10);
    }

    function test_Mint_RevertsOnZeroVotingPower() external {
        vm.expectRevert(MembershipNFT.MembershipNFT__ZeroVotingPower.selector);
        vm.prank(minter);
        nft.mint(alice, 0);
    }

    // ==================================
    // ====== recordVote Tests ==========
    // ==================================

    /*
    test_RecordVote_OnlyGovernorCanCall — non-governor reverts
    test_RecordVote_IncrementsVotesCast — single call: votesCast goes from 0 to 1
    test_RecordVote_AccumulatesAcrossMultipleCalls — 5 calls → votesCast == 5
    test_RecordVote_EmitsVoteRecordedEvent — verify event
    test_RecordVote_RevertsOnNonexistentToken — try to record vote for tokenId 999, should revert via _requireOwned
    */

    // ==================================
    // ======= Soulbound Tests ==========
    // ==================================

    /*
    test_Soulbound_TransferReverts — mint to alice, alice tries to transfer to bob, reverts
    test_Soulbound_SafeTransferFromReverts — same but via safeTransferFrom
    test_Soulbound_ApprovalDoesNotEnableTransfer — alice approves bob, bob calls transferFrom, still reverts
    */

    // ==================================
    // ==== ERC721Votes Integration =====
    // ==================================

    /*
    test_Votes_GetVotesReflectsVotingPower — mint with power=10, getVotes returns 10
    test_Votes_GetVotesSumsAcrossMultipleNFTs — mint two NFTs (power 10 and 15) to alice, getVotes returns 25
    test_Votes_GetPastVotesAtHistoricalBlock — mint, advance block, mint again, getPastVotes at earlier block returns earlier voting power
    test_Votes_VotingPowerIndependentOfBalanceOf — mint power=100 NFT, verify balanceOf returns 1 (not 100). This catches the bug where someone thinks ERC721Votes uses balanceOf.
    */

    // ==================================
    // ======== tokenURI Tests ==========
    // ==================================

    /*
    test_TokenURI_Tier0_ForNewcomer — votesCast == 0, decoded JSON contains "Newcomer" and the gray SVG color
    test_TokenURI_Tier1_AfterFiveVotes — record 5 votes, decoded JSON contains "Active"
    test_TokenURI_Tier2_AtBoundary20 — record 20 votes (boundary), decoded JSON contains "Engaged"
    test_TokenURI_Tier3_AtTwentyOne — record 21 votes, decoded JSON contains "Veteran"
    test_TokenURI_RevertsForNonexistentToken — query tokenId 999, should revert

    For the tokenURI tests: you don't need to fully Base64-decode and parse JSON in Solidity. Two approaches:

    Use console.log to print the encoded result, decode externally, paste into a comment for documentation
    Or just check that the result is non-empty and starts with the right prefix (data:application/json;base64,)

    The richer test pattern: use Forge's vm cheatcodes to decode and assert specific substrings. But this is verbose. For a portfolio project, asserting prefix + nonempty is acceptable. Note in a comment that "full JSON parsing requires off-chain decoding."
    */

    // ==================================
    // ========== View Tests ============
    // ==================================

    /*
    test_GetVotingPowerOf_ReturnsCorrectValue — straightforward
    test_GetVotesCastOf_ReturnsCorrectValue — straightforward
    test_GetTokenCounter_IncrementsAfterMint — mint, getTokenCounter increases
    */
}
