# NFT-Gated Membership DAO — Design Document

## Problem Statement

### The Setting

A community is bootstrapping a DAO.

A pre-verified list of contributors (the **VIP List**) can claim free, soulbound Membership NFTs that grant governance voting power. The NFT's appearance dynamically upgrades on-chain based on governance participation.

Members govern a treasury through a standard:

```text
Propose → Vote → Timelock → Execute
```

governance lifecycle.

### Actors

#### Eligible Claimant

* Included in the Merkle allowlist.
* Signs an EIP-712 claim message.
* Pays **0 gas**.

#### Relayer

* Submits claim transactions on behalf of users.
* Pays gas costs.
* Receives no economic reward.

#### Member

* Holds a Membership NFT.
* Can propose governance actions.
* Can vote on proposals.
* Can queue and execute approved proposals.

### What This Protocol Is Not

The protocol intentionally excludes:

* Tradeable ERC20 governance tokens.
* Upgradeable contracts.
* Fundraising mechanisms.
* Stackable memberships.

Each address may hold **at most one Membership NFT**.

---

# Architecture

## Contracts

### TreasuryToken.sol

Standard ERC20 token representing DAO treasury assets.

**Role:** Foundational

---

### MembershipNFT.sol

Soulbound ERC721 membership token.

Responsibilities:

* Tracks custom voting power.
* Tracks governance participation.
* Generates dynamic on-chain SVG metadata.
* Enforces one NFT per address.

**Role:** Foundational

---

### MerkleClaim.sol

Gasless claim contract.

Responsibilities:

* Verifies Merkle proofs.
* Verifies EIP-712 signatures.
* Authorizes NFT minting.

**Depends On:** MembershipNFT

---

### TimelockController.sol

OpenZeppelin Timelock contract.

Responsibilities:

* Holds treasury assets.
* Enforces mandatory execution delay.

**Role:** Standard OpenZeppelin Module

---

### MembershipGovernor.sol

Customized OpenZeppelin Governor.

Responsibilities:

* Reads voting power from MembershipNFT.
* Manages proposals and voting.
* Queues and executes through Timelock.

**Depends On:**

* MembershipNFT
* TimelockController

---

### Box.sol

Simple target contract used to demonstrate governance execution.

**Role:** External State Target

---

## Interfaces

### IMembershipNFT

Exposes minting functionality only.

Consumed by:

* MerkleClaim

### IMembershipVoter

Exposes voting-related functionality only.

Consumed by:

* MembershipGovernor

This separation enforces the **Principle of Least Privilege**.

---

# Intentional Omissions

## Upgradeability

No proxy patterns are used.

Contracts are immutable after deployment.

Future upgradeability experiments are deferred to separate projects exploring:

* UUPS
* Beacon Proxies

---

## Transferability

Membership NFTs are strictly soulbound.

The following transfer paths are disabled:

* `transferFrom`
* `safeTransferFrom`
* Any alternative transfer mechanism

---

## Public Minting

No public mint function exists.

All minting must pass through:

1. Merkle proof verification.
2. EIP-712 signature verification.

---

## Token Sale

The protocol includes no funding mechanism.

Treasury assets are seeded during deployment.

---

## ERC721Enumerable

OpenZeppelin's `ERC721Enumerable` extension is intentionally omitted.

Since each address may hold only one NFT, the protocol uses:

```solidity
mapping(address => uint256) s_tokenIdOf;
```

for O(1) ownership lookups.

This avoids the additional gas overhead of full enumeration.

---

# Design Decisions & Trade-Offs

## One NFT Per Address

The protocol originally supported multiple NFTs per wallet.

This was redesigned to enforce a strict one-to-one relationship because:

1. Membership represents identity rather than balance.
2. Voting lookups become O(1).
3. Double-counting attack surfaces disappear.

---

## Token IDs Start at 1

Token IDs intentionally begin at `1`.

```solidity
s_tokenIdOf[account] == 0
```

acts as a sentinel value meaning:

```text
No NFT Owned
```

Starting token IDs at 1 guarantees that token ownership can never be confused with an uninitialized mapping value.

---

## Interface Segregation

Two separate interfaces are maintained:

### IMembershipNFT

Used only by MerkleClaim.

### IMembershipVoter

Used only by MembershipGovernor.

Benefits:

* Reduced coupling.
* Smaller attack surface.
* Principle of Least Knowledge.

Cost:

* One additional interface file.

---

## `_safeMint` Instead of `_mint`

The protocol intentionally uses:

```solidity
_safeMint(...)
```

instead of:

```solidity
_mint(...)
```

This ensures contract recipients correctly implement:

```solidity
IERC721Receiver
```

The trade-off is potential mint failures for incompatible delegated contracts (such as certain EIP-7702 configurations).

The benefit is safer NFT delivery semantics.

---

## Circular Dependency Deployment

MembershipNFT and MerkleClaim reference each other immutably.

This dependency is resolved during deployment using:

```solidity
vm.computeCreateAddress(...)
```

The deployment script predicts the future MerkleClaim address before MembershipNFT deployment.

The script then asserts the prediction matches the actual deployment address.

---

# State Model

## MembershipNFT

### Voting Power

```solidity
mapping(uint256 => uint256) private s_votingPower;
```

Stores custom voting weight per NFT.

---

### Governance Participation

```solidity
mapping(uint256 => uint256) private s_votesCast;
```

Tracks votes cast and drives SVG evolution.

---

### Ownership Lookup

```solidity
mapping(address => uint256) private s_tokenIdOf;
```

Provides O(1) token lookup.

Returns:

* Token ID if owned.
* `0` if no NFT exists.

---

### Additional State

* Sequential token counter (starts at 1).
* Authorized minter address (`MerkleClaim`).

---

## MerkleClaim

### Merkle Root

```solidity
bytes32 immutable i_merkleRoot;
```

Set during deployment.

---

### NFT Contract Reference

```solidity
address immutable i_membershipNFT;
```

---

### Replay Protection

```solidity
mapping(address => bool) hasClaimed;
```

---

### EIP-712 State

Includes:

* Chain ID
* Contract Address
* Domain Separator

---

## Governor & Timelock

Maintain standard OpenZeppelin Governor state.

---

# Core Functions

## MembershipNFT

### `mint(address to, uint256 votingPower)`

* Only callable by MerkleClaim.
* Reverts if the recipient already owns an NFT.
* Automatically self-delegates voting power.

---

### `recordVote(uint256 tokenId)`

* Only callable by MembershipGovernor.
* Increments governance participation count.

---

### `tokenURI(uint256 tokenId)`

Returns Base64-encoded JSON metadata containing dynamic SVG artwork derived from governance participation.

---

### `_update(address to, uint256 tokenId, address auth)`

Overridden to:

* Allow minting (`from == address(0)`).
* Revert on transfers.
* Revert on burns.

This enforces soulbound behavior.

---

### `_getVotingUnits(address account)`

Reads voting power by first looking up the user's token ID via `s_tokenIdOf`, then querying `s_votingPower[tokenId]`.

Returns `0` if the account does not own a Membership NFT.

---

### `tokenIdOf(address account)`

Returns:

* The Membership NFT token ID.
* `0` if the account owns no NFT.

---

## MerkleClaim

### `claim(...)`

Called by a relayer.

Validates:

* Merkle proof
* EIP-712 signature

Then mints the Membership NFT.

---

### `getMessageHash(...)`

Returns the EIP-712 digest signed by claimants.

---

## MembershipGovernor

### `_castVote(...)`

Customized Governor hook.

Records governance participation inside MembershipNFT whenever a vote is successfully cast.

---

# Invariants

## One Claim Per Address

```text
hasClaimed[account]
```

is strictly monotonic.

Once true, it can never become false.

**Enforced by:** `claim()` sets `hasClaimed[account] = true` after successful verification, and no code path resets the value.

**Verified by:** `invariant_HasClaimedIsMonotonic`.

---

## Conservation of Voting Power

The total voting power minted must equal the total voting power represented by claimed Merkle leaves.

**Enforced by:** Voting power is derived directly from Merkle leaf data and can only be minted after successful Merkle proof and EIP-712 signature verification. Arbitrary voting power cannot be created.

---

## Soulbound Integrity

NFT ownership is immutable after minting.

Transfers and burns cannot occur.

**Enforced by:** The overridden `_update()` function reverts whenever `from != address(0)`, blocking all transfers and burns while allowing mints.

**Verified by:** `test_Soulbound_*` unit tests.

---

## Vote Monotonicity

```text
votesCast[tokenId]
```

is non-decreasing.

Votes may increase but never decrease.

**Enforced by:** `recordVote()` only increments vote counts. No decrement path exists.

**Verified by:** `invariant_VotesCastMatchesExpected`.

---

## Treasury Safety

Treasury assets may leave the Timelock only through:

```text
Queued Proposal → Timelock Delay → Successful Execution
```

**Enforced by:** OpenZeppelin Timelock role-based access control.

---

## Signature Replay Protection

Signatures cannot be replayed:

* On the same chain
* Across chains
* Across forks

**Enforced by:** The `hasClaimed` replay-protection mapping combined with the EIP-712 domain separator containing both `chainId` and `address(this)`.

---

## Supply-Claim Consistency & One-NFT-Per-Address

The following must always hold:

```text
totalSupply == claimedMembers
```

and

```text
balanceOf(account) <= 1
```

for every account.

**Enforced by:** Each successful claim mints exactly one NFT and increments supply. Minting reverts if an account already owns an NFT.

**Verified by:**

* `invariant_SupplyMatchesClaimedCount`
* `invariant_OneNFTPerAddress`

---

# Threat Model

## Cryptographic Threats

### Cross-Chain Replay

**Mitigation:** EIP-712 domain includes `chainId`.

---

### Same-Chain Replay

**Mitigation:** `hasClaimed` replay protection mapping.

---

### Fork Replay

**Mitigation:** Contract address included in the EIP-712 domain separator.

---

### Merkle Forgery

**Mitigation:** OpenZeppelin's double-hashed Merkle leaf structure prevents second-preimage attacks.

---

### Signature Malleability

**Mitigation:** OpenZeppelin's ECDSA implementation rejects high-`s` signatures.

---

## Authorization Threats

### Unauthorized Minting

**Mitigation:** `onlyMinter` restriction locks minting to the MerkleClaim contract.

---

### Soulbound Bypass

**Mitigation:** The `_update()` override reverts all transfer attempts.

---

### Double Minting

**Mitigation:** Minting reverts if the recipient already owns a Membership NFT before any state mutation occurs.

---

## Governance Threats

### Flash-Loan Voting

**Mitigation:** ERC721Votes checkpointing combined with soulbound illiquidity. NFTs cannot be borrowed or transferred during voting.

---

### Dormant Voting Power

ERC721Votes normally requires explicit delegation.

Users who forget to delegate become unintentionally disenfranchised.

**Mitigation:** Automatic self-delegation during minting.

---

### Front-Running Claims

Expected behavior.

The relayer may submit the transaction first, but ownership always resolves to the cryptographically verified claimant.

---

### Treasury Drain

**Mitigation:** Timelock delay provides a mandatory community review and cancellation window before execution.
