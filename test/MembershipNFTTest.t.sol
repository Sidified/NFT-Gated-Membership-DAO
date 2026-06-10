// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MembershipNFT} from "../src/MembershipNFT.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

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

    // non-governor reverts
    function test_RecordVote_OnlyGovernorCanCall() external {
        vm.prank(minter);
        nft.mint(alice, 10);

        vm.expectRevert(MembershipNFT.MembershipNFT__OnlyGovernor.selector);
        vm.prank(alice); // even alice (the token owner) can't call this
        nft.recordVote(0);
    }

    // single call: votesCast goes from 0 to 1
    function test_RecordVote_IncrementsVotesCast() external {
        vm.prank(minter);
        nft.mint(alice, 10);

        vm.prank(governor);
        nft.recordVote(0);

        assertEq(nft.getVotesCastOf(0), 1, "votesCast should be 1 after single recordVote");
    }

    // single call: votesCast goes from 0 to 1
    function test_RecordVote_AccumulatesAcrossMultipleCalls() external {
        vm.prank(minter);
        nft.mint(alice, 10);

        vm.startPrank(governor);
        for (uint256 i = 0; i < 5; i++) {
            nft.recordVote(0);
        }
        vm.stopPrank();

        assertEq(nft.getVotesCastOf(0), 5, "votesCast should accumulate to 5");
    }

    // verify event
    function test_RecordVote_EmitsVoteRecordedEvent() external {
        vm.prank(minter);
        nft.mint(alice, 10);

        vm.expectEmit(true, false, false, true, address(nft));
        emit MembershipNFT.VoteRecorded(0, 1); // tokenId 0, newVotesCast 1

        vm.prank(governor);
        nft.recordVote(0);
    }

    // try to record vote for tokenId 999, should revert via _requireOwned
    function test_RecordVote_RevertsOnNonexistentToken() external {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 999));
        vm.prank(governor);
        nft.recordVote(999);
    }

    // ==================================
    // ======= Soulbound Tests ==========
    // ==================================

    // mint to alice, alice tries to transfer to bob, reverts
    function test_Soulbound_TransferReverts() external {
        vm.prank(minter);
        nft.mint(alice, 10);

        vm.prank(alice);
        vm.expectRevert(MembershipNFT.MembershipNFT__Soulbound.selector);
        nft.transferFrom(alice, bob, 0);
    }

    // same but via safeTransferFrom
    function test_Soulbound_SafeTransferFromReverts() external {
        vm.prank(minter);
        nft.mint(alice, 10);

        vm.prank(alice);
        vm.expectRevert(MembershipNFT.MembershipNFT__Soulbound.selector);
        nft.safeTransferFrom(alice, bob, 0);
    }

    // alice approves bob, bob calls transferFrom, still reverts
    function test_Soulbound_ApprovalDoesNotEnableTransfer() external {
        vm.prank(minter);
        nft.mint(alice, 10);

        // Alice approves bob as a spender. Approval itself is allowed (no override on approve()).
        vm.prank(alice);
        nft.approve(bob, 0);

        // Bob attempts to use his approval to transfer alice's token to charlie.
        // This must revert: approval doesn't bypass soulbound enforcement.
        vm.prank(bob);
        vm.expectRevert(MembershipNFT.MembershipNFT__Soulbound.selector);
        nft.transferFrom(alice, charlie, 0); // Note: from=alice (owner), not from=bob
    }

    // ==================================
    // ==== ERC721Votes Integration =====
    // ==================================

    // mint, advance block, mint again, getPastVotes at earlier block returns earlier voting power
    function test_Votes_GetPastVotesAtHistoricalBlock() external {
        vm.prank(minter);
        nft.mint(alice, 10);
        uint256 mintBlock1 = block.number;

        vm.roll(10);
        vm.prank(minter);
        nft.mint(alice, 20);
        uint256 mintBlock2 = block.number;

        vm.roll(20);
        vm.prank(minter);
        nft.mint(alice, 30);
        uint256 mintBlock3 = block.number;

        // Advance the block so mintBlock3 is now officially in the past
        vm.roll(mintBlock3 + 1);

        assertEq(nft.getPastVotes(alice, mintBlock1), 10, "votes at first mint block should be 10");
        assertEq(nft.getPastVotes(alice, mintBlock2), 30, "votes at second mint block should be 30");
        assertEq(nft.getPastVotes(alice, mintBlock3), 60, "votes at third mint block should be 60");

        // At block 5 (between mint 1 and mint 2), the most recent checkpoint is mint 1.
        // OZ returns the most recent value at-or-before the queried block.
        assertEq(nft.getPastVotes(alice, 5), 10, "votes between mints should reflect prior checkpoint");
    }

    // mint power=100 NFT, verify balanceOf returns 1 (not 100). This catches the bug where someone thinks ERC721Votes uses balanceOf.
    function test_Votes_VotingPowerIndependentOfBalanceOf() external {
        vm.prank(minter);
        nft.mint(alice, 100);

        assertEq(nft.balanceOf(alice), 1, "balanceOf should be 1 (one NFT)");
        assertEq(nft.getVotes(alice), 100, "getVotes should be 100 (custom voting power)");
    }

    function test_Votes_GetPastVotesRevertsOnCurrentBlock() external {
        vm.prank(minter);
        nft.mint(alice, 10);

        vm.expectRevert(); // OZ's ERC5805FutureLookup; using bare expectRevert for simplicity
        nft.getPastVotes(alice, block.number);
    }

    // ==================================
    // ======== tokenURI Tests ==========
    // ==================================

    // votesCast == 0, decoded JSON contains "Newcomer" and the gray SVG color
    function test_TokenURI_Tier0_Newcomer() external {
        // Setup: Mint Alice an NFT. 0 votes cast by default.
        vm.prank(minter);
        nft.mint(alice, 10);

        // Generate the expected output using the shadow helper
        string memory expected = _expectedTokenURI(0, "Newcomer", 0, "#888");

        // Get the actual output from the contract
        string memory actual = nft.tokenURI(0);

        assertEq(actual, expected, "Tier 0 tokenURI mismatch");
    }

    // record 5 votes, decoded JSON contains "Active"
    function test_TokenURI_Tier1_AfterFiveVotes() external {
        // Setup: Mint Alice an NFT. 0 votes cast by default.
        vm.prank(minter);
        nft.mint(alice, 10);

        vm.startPrank(governor);
        for (uint256 i = 0; i < 5; i++) {
            nft.recordVote(0);
        }
        vm.stopPrank();

        // Generate the expected output using the shadow helper
        string memory expected = _expectedTokenURI(0, "Active", 5, "#4a90e2");

        // Get the actual output from the contract
        string memory actual = nft.tokenURI(0);
        assertEq(actual, expected, "Tier 1 tokenURI mismatch");
    }

    // record 20 votes (boundary), decoded JSON contains "Engaged"
    function test_TokenURI_Tier2_AtBoundary20() external {
        // Setup: Mint Alice an NFT. 0 votes cast by default.
        vm.prank(minter);
        nft.mint(alice, 10);

        vm.startPrank(governor);
        for (uint256 i = 0; i < 20; i++) {
            nft.recordVote(0);
        }
        vm.stopPrank();

        // Generate the expected output using the shadow helper
        string memory expected = _expectedTokenURI(0, "Engaged", 20, "#9b59b6");

        // Get the actual output from the contract
        string memory actual = nft.tokenURI(0);
        assertEq(actual, expected, "Tier 2 tokenURI mismatch");
    }

    // record 21 votes, decoded JSON contains "Veteran"
    function test_TokenURI_Tier3_AtTwentyOne() external {
        // Setup: Mint Alice an NFT. 0 votes cast by default.
        vm.prank(minter);
        nft.mint(alice, 10);

        vm.startPrank(governor);
        for (uint256 i = 0; i < 21; i++) {
            nft.recordVote(0);
        }
        vm.stopPrank();

        // Generate the expected output using the shadow helper
        string memory expected = _expectedTokenURI(0, "Veteran", 21, "#f1c40f");

        // Get the actual output from the contract
        string memory actual = nft.tokenURI(0);
        assertEq(actual, expected, "Tier 3 tokenURI mismatch");
    }

    // query tokenId 999, should revert
    function test_TokenURI_RevertsForNonexistentToken() external {
        vm.expectRevert();
        nft.tokenURI(999);
    }

    // ==================================
    // ========== View Tests ============
    // ==================================

    /*
    test_GetVotingPowerOf_ReturnsCorrectValue — straightforward
    test_GetVotesCastOf_ReturnsCorrectValue — straightforward
    test_GetTokenCounter_IncrementsAfterMint — mint, getTokenCounter increases
    */

    // ==================================
    // ======= Helper Functions =========
    // ==================================

    function _deployFreshNft() internal returns (MembershipNFT) {
        vm.prank(deployer);
        return new MembershipNFT(minter, "Fresh", "FR");
    }

    function _expectedTokenURI(uint256 tokenId, string memory tierName, uint256 votesCast, string memory svgFillColor)
        internal
        pure
        returns (string memory)
    {
        string memory svg = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200"><circle cx="100" cy="100" r="80" fill="',
                svgFillColor,
                '"/></svg>'
            )
        );

        string memory imageURI = string(abi.encodePacked("data:image/svg+xml;base64,", Base64.encode(bytes(svg))));

        string memory description = string(
            abi.encodePacked(
                "Soulbound governance membership. Tier: ", tierName, ". Votes cast: ", Strings.toString(votesCast)
            )
        );

        string memory json = string(
            abi.encodePacked(
                '{"name": "Membership #',
                Strings.toString(tokenId),
                '", "description": "',
                description,
                '", "image": "',
                imageURI,
                '"}'
            )
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }
}
