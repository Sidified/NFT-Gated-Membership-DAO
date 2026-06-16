# NFT-Gated Membership DAO: Design Document

## Problem Statement
**The Setting:** A community bootstrapping a DAO. A pre-verified list of contributors (the VIP list) claims free, soulbound membership NFTs that grant governance voting power. The NFT's appearance dynamically upgrades on-chain based on governance participation. Members govern a treasury via a standard propose -> vote -> timelock -> execute flow.

**The Actors:**
- *Eligible Claimant:* On the Merkle list. Signs EIP-712 claim message. Pays 0 gas.
- *Relayer:* Submits the claim transaction. Pays gas. No economic reward.
- *Member:* Holds the NFT. Can propose, vote, and trigger queued executions.

**What this protocol is NOT:** A tradeable ERC20 governance token, an upgradable system, or a fundraiser. Not a stackable membership. Each address can hold at most one Membership NFT.

## Architecture
1. **TreasuryToken.sol:** Fresh, standard ERC20 representing the DAO treasury. (Foundational)
2. **MembershipNFT.sol:** Soulbound ERC721. Tracks custom voting power per token. Generates dynamic on-chain SVG based on vote count. Enforces strictly one NFT per address. (Foundational)
3. **MerkleClaim.sol:** Validates off-chain EIP-712 signatures against an immutable Merkle root to authorize gasless minting. (Depends on MembershipNFT)
4. **TimelockController.sol:** Standard OZ vault holding treasury assets with a mandatory execution delay. (Standard OZ)
5. **GovernorContract.sol:** Core OpenZeppelin Governor logic customized to read voting power from MembershipNFT. (Depends on MembershipNFT + Timelock)

## State Model
**MembershipNFT:**
- `mapping(uint256 tokenId => uint256) private s_votingPower` (Custom voting weight per NFT)
- `mapping(uint256 tokenId => uint256) private s_votesCast` (Drives the dynamic SVG tier)
- `mapping(address account => uint256) private s_tokenIdOf` (0 if unminted; tokenIds start at 1. O(1) lookup to find user's token)
- Token counter for sequential IDs (Starts at 1, not 0, to disambiguate the `s_tokenIdOf` mapping).
- Address of authorized minter (`MerkleClaim`).

**MerkleClaim:**
- `bytes32 immutable i_merkleRoot` (Set at deploy).
- `address immutable i_membershipNFT`.
- `mapping(address claimant => bool hasClaimed)` (Replay protection).
- Standard EIP-712 domain state (including chainId and contract address).

**GovernorContract & TimelockController:**
- Standard OpenZeppelin state.

## Functions
**MembershipNFT:**
- `mint(address to, uint256 votingPower)`: Only callable by MerkleClaim. Reverts if `to` already has an NFT. Auto-delegates to the minter.
- `recordVote(uint256 tokenId)`: Only callable by Governor. Increments `votesCast`.
- `tokenURI(uint256 tokenId)`: Returns Base64 JSON with SVG based on `votesCast`.
- `_update(address to, uint256 tokenId, address auth)`: Overridden to revert when `from != address(0)` (blocks transfers/burns while allowing mints).
- `_getVotingUnits(address account)`: Overridden to read from custom `s_votingPower` via `s_tokenIdOf`.
- `tokenIdOf(address account)`: Returns `uint256` - Returns the specific tokenId for an account, or 0 if they hold no NFT.

**MerkleClaim:**
- `claim(...)`: Relayer calls this with Merkle Proof and EIP-712 signature. Calls NFT `mint`.
- `getMessageHash(...)`: Generates the digest for the claimant to sign.

**GovernorContract:**
- `_castVote(...)`: Overridden internal hook to call `MembershipNFT.recordVote(...)`.

## Invariants
1. **One-claim-per-address:** `hasClaimed` is strictly monotonic.
2. **Conservation of Power:** Sum of all minted `votingPower` == Sum of `votingPower` in claimed Merkle leaves.
3. **Soulbound Integrity:** Token ownership is immutable after block X. `_update` blocks transfers/burns.
4. **Vote Monotonicity:** `votesCast` for any token is non-decreasing.
5. **Treasury Safety:** Funds only leave the Timelock via successful, queued DAO proposals.
6. **Signature Replay Protection:** Signatures cannot be reused on the same chain (mapping check) or across forks (Domain Separator).
7. **Supply-Claim Consistency & One-NFT-Per-Address:** The number of minted NFTs equals the number of claimants who have successfully claimed (`totalSupply(MembershipNFT) == count(addresses where hasClaimed == true)`). No address ever holds more than one MembershipNFT. `balanceOf(account) <= 1` for all accounts.

## Threat Model
1. **Cross-Chain Replay:** Mitigated by EIP-712 `chainId` in domain separator.
2. **Same-Chain Replay:** Mitigated by `hasClaimed[account]` check.
3. **Merkle Forgery:** Mitigated by OZ double-hashing leaf structure.
4. **Flash-Loan Voting:** Mitigated by ERC721Votes checkpointing mechanism (and soulbound illiquidity).
5. **Soulbound Bypass:** Mitigated by strictly overriding the `_update` OZ v5 hook to revert on transfers.
6. **Unauthorized Minting:** Mitigated by `onlyMinter` modifier locking mints to `MerkleClaim`.
7. **Dormant Voting Power:** ERC721Votes requires explicit delegation to activate voting power. Holders who forget to delegate are silently disenfranchised, allowing minority capture of governance. Mitigated by auto-delegating to `msg.sender` inside the `mint` function.
8. **EIP-712 Fork Malleability:** Mitigated by including `address(this)` in the domain separator.
9. **Front-running Claims:** Expected behavior. Relayer pays gas, but NFT still goes to the verified claimant.
10. **Double Minting:** A bug or malicious caller mints two NFTs to the same address. Mitigation: `mint` reverts if `balanceOf(to) > 0` (or equivalently, if `s_tokenIdOf[to] != 0`). Enforced at the start of mint, before any state changes.

## Intentional Omissions
- No Upgradability (Proxy patterns deferred to Project 4).
- No Transferability (Soulbound strictness).
- No Public Mint or Token Sale (Treasury seeded at deploy).