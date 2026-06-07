// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721Votes} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Votes.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title MembershipNFT
 * @notice A soulbound ERC721 token that acts as a governance identity for a DAO.
 * @dev Inherits OpenZeppelin's ERC721Votes. Implements custom voting power per token,
 * an internal _update hook to enforce soulbound (non-transferable) mechanics, and an
 * entirely on-chain dynamic SVG metadata engine based on governance participation.
 */
contract MembershipNFT is ERC721Votes {
    //// ERRORS ////
    error MembershipNFT__OnlyMinter();
    error MembershipNFT__OnlyGovernor();
    error MembershipNFT__OnlyDeployer();
    error MembershipNFT__Soulbound();
    error MembershipNFT__GovernorAlreadySet();
    error MembershipNFT__ZeroAddress();
    error MembershipNFT__ZeroVotingPower();

    //// STATE VARIABLES ////
    mapping(uint256 tokenId => uint256) private s_votingPower;
    mapping(uint256 tokenId => uint256) private s_votesCast;
    mapping(address account => uint256) private s_userVotingPower;
    uint256 private s_tokenCounter;
    address private immutable i_minter;
    address private s_governor;
    address private immutable i_deployer;

    //// EVENTS ////

    /**
     * @notice Emitted when a new Membership NFT is claimed and minted.
     * @param to The address receiving the NFT.
     * @param tokenId The unique identifier of the minted NFT.
     * @param votingPower The custom voting weight assigned to this specific NFT.
     */
    event Minted(address indexed to, uint256 indexed tokenId, uint256 votingPower);

    /**
     * @notice Emitted when the Governor contract records a vote for this token.
     * @param tokenId The token that voted.
     * @param newVotesCast The updated total number of votes cast by this token.
     */
    event VoteRecorded(uint256 indexed tokenId, uint256 newVotesCast);

    /**
     * @notice Emitted when the deployer sets the Governor address.
     * @param governor The address of the authorized Governor contract.
     */
    event GovernorSet(address indexed governor);

    //// MODIFIERS ////
    modifier onlyMinter() {
        if (msg.sender != i_minter) revert MembershipNFT__OnlyMinter();
        _;
    }
    modifier onlyGovernor() {
        if (msg.sender != s_governor) revert MembershipNFT__OnlyGovernor();
        _;
    }
    modifier onlyDeployer() {
        if (msg.sender != i_deployer) revert MembershipNFT__OnlyDeployer();
        _;
    }

    //// CONSTRUCTOR ////

    /**
     * @notice Initializes the NFT contract and sets the authorized minter.
     * @param minter The address of the MerkleClaim contract authorized to mint.
     * @param name The name of the NFT collection.
     * @param symbol The symbol of the NFT collection.
     */
    constructor(address minter, string memory name, string memory symbol) ERC721(name, symbol) EIP712(name, "1") {
        i_minter = minter;
        i_deployer = msg.sender;
    }

    //// EXTERNAL FUNCTIONS ////

    /**
     * @notice Mints a new soulbound membership NFT to a verified contributor.
     * @dev Automatically delegates voting power on the first mint to activate governance checkpoints.
     * For subsequent mints, it bypasses standard OpenZeppelin logic and manually injects the new
     * voting power into the existing checkpoint ledger to prevent double-counting.
     * @param to The address of the verified contributor.
     * @param votingPower The amount of voting power the contributor earned.
     */
    function mint(address to, uint256 votingPower) external onlyMinter {
        if (to == address(0)) revert MembershipNFT__ZeroAddress();
        if (votingPower == 0) revert MembershipNFT__ZeroVotingPower();

        uint256 tokenId = s_tokenCounter;
        s_tokenCounter++;
        s_votingPower[tokenId] = votingPower;
        s_userVotingPower[to] += votingPower;

        // Auto-delegate to self on first mint; subsequent mints inherit the delegation.
        if (delegates(to) == address(0)) {
            _delegate(to, to);
        } else {
            // Already delegated; manually move voting units to update the checkpoint
            // since we've bypassed OZ's automatic _transferVotingUnits in _update and _increaseBalance.
            _transferVotingUnits(address(0), to, votingPower);
        }

        _safeMint(to, tokenId);

        emit Minted(to, tokenId, votingPower);
    }

    /**
     * @notice Increments the vote counter for a specific token, allowing its visual tier to upgrade.
     * @dev Can only be called by the authorized Governor contract.
     * @param tokenId The ID of the token that just cast a vote.
     */
    function recordVote(uint256 tokenId) external onlyGovernor {
        _requireOwned(tokenId);

        s_votesCast[tokenId]++;

        emit VoteRecorded(tokenId, s_votesCast[tokenId]);
    }

    /**
     * @notice Links this NFT contract to the DAO's Governor contract.
     * @dev A one-time setter to solve the deployment chicken-and-egg problem.
     * @param governor The address of the deployed Governor contract.
     */
    function setGovernor(address governor) external onlyDeployer {
        if (governor == address(0)) revert MembershipNFT__ZeroAddress();
        if (s_governor != address(0)) revert MembershipNFT__GovernorAlreadySet();
        s_governor = governor;
        emit GovernorSet(governor);
    }

    //// PUBLIC VIEW FUNCTIONS ////

    /**
     * @notice Returns the fully constructed, Base64-encoded JSON metadata for the token.
     * @dev Generates an on-chain SVG and dynamic description based on the token's vote count tier.
     * @param tokenId The ID of the token to query.
     * @return A Base64 string containing the JSON metadata and encoded SVG.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        // 1. Gather all dynamic state variables
        uint256 votesCast = s_votesCast[tokenId];
        uint256 tier = _getTier(votesCast);
        string memory svg = _getTierSvg(tier);
        string memory tierName = _getTierName(tier);

        // 2. Encode the SVG
        string memory encodedSvg = Base64.encode(bytes(svg));
        string memory imageURI = string(abi.encodePacked("data:image/svg+xml;base64,", encodedSvg));

        // 3. Construct the dynamic description string
        string memory description = string(
            abi.encodePacked(
                "Soulbound governance membership. Tier: ", tierName, ". Votes cast: ", Strings.toString(votesCast)
            )
        );

        // 4. Construct the final JSON string
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

        // 5. Encode the JSON in Base64 and return
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    /**
     * @notice Retrieves the static voting power assigned to a specific token.
     * @param tokenId The ID of the token.
     * @return The voting power integer.
     */
    function getVotingPowerOf(uint256 tokenId) public view returns (uint256) {
        return s_votingPower[tokenId];
    }

    /**
     * @notice Retrieves the total number of votes cast by a specific token.
     * @param tokenId The ID of the token.
     * @return The number of votes cast.
     */
    function getVotesCastOf(uint256 tokenId) public view returns (uint256) {
        return s_votesCast[tokenId];
    }

    /**
     * @notice Returns the address authorized to mint NFTs.
     * @return The minter's address.
     */
    function getMinter() public view returns (address) {
        return i_minter;
    }

    /**
     * @notice Returns the address of the authorized Governor contract.
     * @return The Governor's address.
     */
    function getGovernor() public view returns (address) {
        return s_governor;
    }

    /**
     * @notice Returns the next available token ID to be minted.
     * @return The next token ID.
     */
    function getTokenCounter() public view returns (uint256) {
        return s_tokenCounter;
    }

    //// INTERNAL OVERRIDES FUNCTIONS ////

    /**
     * @notice Intercepts all token movements to enforce the soulbound restriction.
     * @dev Reverts if the 'from' address is not the zero address, allowing mints but blocking transfers/burns.
     */
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721Votes) returns (address) {
        address from = _ownerOf(tokenId);

        if (from != address(0)) {
            revert MembershipNFT__Soulbound();
        }

        // Call ERC721._update directly, bypassing ERC721Votes._update which would
        // add +1 to voting checkpoints via _transferVotingUnits. Voting power is
        // managed exclusively by our custom s_userVotingPower mapping via _delegate.
        return ERC721._update(to, tokenId, auth);
    }

    /**
     * @notice Overrides standard NFT counting to use custom voting power mapping.
     * @dev Required by OpenZeppelin's Votes contract to determine an account's true weight.
     */
    function _getVotingUnits(address account) internal view override returns (uint256) {
        return s_userVotingPower[account];
    }

    /**
     * @notice Hook to update ERC721 token balances when a token is minted or transferred.
     * @dev We explicitly bypass the ERC721Votes parent implementation and route directly
     * to ERC721._increaseBalance. This prevents OpenZeppelin's internal machinery from
     * automatically adding +1 voting unit to the governance checkpoints, as we handle
     * custom voting weights manually during minting.
     */
    function _increaseBalance(address account, uint128 amount) internal override(ERC721Votes) {
        // Bypass Votes._increaseBalance which would add `amount` to voting checkpoints
        // via _transferVotingUnits. Only update the ERC721 balance counter.
        ERC721._increaseBalance(account, amount);
    }

    //// PRIVATE HELPERS ////

    /**
     * @notice Calculates the visual tier of the NFT based on votes cast.
     * @param votesCast The total number of votes cast by the token.
     * @return tier An integer (0-3) representing the achievement tier.
     */
    function _getTier(uint256 votesCast) private pure returns (uint256) {
        if (votesCast == 0) return 0;
        if (votesCast <= 5) return 1;
        if (votesCast <= 20) return 2;
        return 3;
    }

    /**
     * @notice Generates the raw SVG string for a given visual tier.
     * @param tier The tier integer (0-3).
     * @return svg The raw XML/SVG string.
     */
    function _getTierSvg(uint256 tier) private pure returns (string memory svg) {
        if (tier == 0) {
            return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200"><circle cx="100" cy="100" r="80" fill="#888"/></svg>';
        }
        if (tier == 1) {
            return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200"><circle cx="100" cy="100" r="80" fill="#4a90e2"/></svg>';
        }
        if (tier == 2) {
            return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200"><circle cx="100" cy="100" r="80" fill="#9b59b6"/></svg>';
        }
        return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200"><circle cx="100" cy="100" r="80" fill="#f1c40f"/></svg>';
    }

    /**
     * @notice Converts a numeric tier into its corresponding human-readable title.
     * @param tier The tier integer (0-3).
     * @return The string representing the tier's name (e.g., "Newcomer", "Veteran").
     */
    function _getTierName(uint256 tier) private pure returns (string memory) {
        if (tier == 0) return "Newcomer";
        if (tier == 1) return "Active";
        if (tier == 2) return "Engaged";
        return "Veteran";
    }
}
