# Smart Contract Security Lab

A Foundry-based lab to learn smart contract security by reproducing real vulnerabilities, writing PoCs, and proposing fixes.

This repo is built **day by day**, not all at once.  
Each day adds one small, working piece: a vulnerable contract, an attacker, a fix, or a report.

## Status

- ✅ **Reentrancy** module complete — vulnerable contract, attacker, fix, 3 passing tests, audit-style writeup
- ✅ **Access Control** module complete — vulnerable + fixed contracts, 5 passing tests, audit-style writeup
- ✅ **Signature Replay** module complete — vulnerable airdrop, fixed implementation, 3 passing tests, audit-style writeup
- 🟡 **Oracle Manipulation** module in progress — vulnerable + fixed lending, TWAP oracle, 4 passing tests; report pending
- ⚪ Upgradeable Proxy — planned

## Reentrancy — Vulnerable Vault, Exploit PoC, Fix, and Writeup

- [x] `src/reentrancy/VulnerableVault.sol`
  A minimal ETH vault that sends ETH to the user **before** updating the user's balance, which makes it vulnerable to reentrancy.
- [x] `src/reentrancy/ReentrancyAttacker.sol`
  Attacker contract that re-enters `withdraw` from `receive()` to drain the vault.
- [x] `src/reentrancy/FixedVault.sol`
  Hardened vault using checks-effects-interactions and OpenZeppelin's `ReentrancyGuard` (defense in depth).
- [x] `test/reentrancy/ReentrancyPoC.t.sol`
  Foundry PoC test suite:
  - `testExploit_DrainsVault` — the attack drains a 10 ETH vault with 1 ETH of attacker capital
  - `testFix_BlocksReentrancy` — the same attacker against `FixedVault` reverts and victim funds remain safe
  - `testFix_AllowsHonestWithdraw` — sanity check that the fix does not break legitimate users
- [x] [`reports/01-reentrancy.md`](reports/01-reentrancy.md)
  Audit-style writeup: severity, summary, root cause, PoC, recommendation, fixed implementation, and learnings.

## Access Control — Vulnerable Treasury, Exploit PoC, Fix

- [x] `src/access-control/VulnerableTreasury.sol`
  A protocol treasury with an `owner` field, but `withdraw` and `setOwner` have **no access checks** — two independent bugs.
- [x] `src/access-control/FixedTreasury.sol`
  Hardened treasury using OpenZeppelin `Ownable` and `onlyOwner` on sensitive functions (no separate attacker contract needed; EOA can exploit the vulnerable version).
- [x] `test/access-control/AccessControlPoC.t.sol`
  Foundry PoC test suite:
  - `testExploit_AnyoneCanDrainTreasury` — any account can call `withdraw` and drain all ETH
  - `testExploit_AnyoneCanBecomeOwner` — any account can call `setOwner` and seize ownership
  - `testFix_BlocksUnauthorizedWithdraw` — attacker `withdraw` reverts with `OwnableUnauthorizedAccount`
  - `testFix_BlocksUnauthorizedSetOwner` — attacker `setOwner` reverts; owner unchanged
  - `testFix_AllowsOwnerFunctions` — legitimate owner can still withdraw and transfer ownership
- [x] [`reports/02-access-control.md`](reports/02-access-control.md)
  Audit-style writeup: two findings (`withdraw`, `setOwner`), severity, PoC, recommendation, fixed implementation, and learnings.

## Signature Replay — Vulnerable Airdrop, Replay PoC, Fix, and Writeup

- [x] `src/signature-replay/VulnerableAirdrop.sol`
  A deliberately vulnerable ETH airdrop that accepts an off-chain signature from a trusted signer, but the signed message only binds `account` and `amount`.
- [x] `test/signature-replay/SignatureReplayPoC.t.sol`
  Foundry PoC test suite:
  - `testExploit_SameSignatureClaimsTwice` — reuses the exact same signature twice and proves the claimant receives the airdrop twice
  - `testFix_BlocksSignatureReplay` — proves the fixed contract consumes the user's nonce and rejects the replayed signature
  - `testFix_RejectsExpiredSignature` — proves expired signatures cannot be used
- [x] `src/signature-replay/FixedAirdrop.sol`
  Fixed implementation: binds signatures to nonce, deadline, chain id, and `address(this)`.
- [x] [`reports/03-signature-replay.md`](reports/03-signature-replay.md)
  Audit-style writeup: severity, replay impact, root cause, PoC, recommendation, fixed implementation, and learnings.

## Oracle Manipulation — AMM Spot Price PoC

- [x] `src/oracle-manipulation/SimpleAMM.sol`
  A deliberately simplified constant-product AMM whose spot price can be moved by changing reserves.
- [x] `src/oracle-manipulation/VulnerableLending.sol`
  A toy lending market that directly trusts the AMM spot price to calculate borrowing power.
- [x] `src/oracle-manipulation/TWAPOracle.sol`
  Records cumulative AMM prices so lending can consult a time-weighted average instead of spot.
- [x] `src/oracle-manipulation/FixedLending.sol`
  Hardened lending market that prices collateral with `TWAPOracle.consult()` instead of `getSpotPrice()`.
- [x] `test/oracle-manipulation/OracleManipulationPoC.t.sol`
  Foundry PoC test suite:
  - `testExploit_SpotPriceManipulationInflatesBorrowLimit` — proves manipulating the AMM spot price inflates the borrow limit and drains pool liquidity
  - `testNormalPriceOnlyAllowsLimitedBorrow` — sanity check showing the normal price only allows a much smaller borrow
  - `testFix_BlocksSpotPriceManipulation` — proves the same manipulation cannot drain the pool when TWAP pricing is used
  - `testFix_AllowsHonestBorrow` — sanity check that legitimate users can still borrow against the TWAP price
- [ ] `reports/04-oracle-manipulation.md`
  Planned audit-style writeup covering spot price risk, root cause, PoC, and mitigation.

## Project Structure

```text
smart-contract-security-lab/
├─ foundry.toml         # Foundry config + remappings
├─ foundry.lock         # Locked dependency versions
├─ .gitmodules          # Git submodules (forge-std, openzeppelin-contracts)
├─ .gitignore
├─ remappings.txt       # IDE-friendly remappings (mirrors foundry.toml)
├─ README.md
├─ lib/
│  ├─ forge-std/             # Foundry standard testing library (submodule)
│  └─ openzeppelin-contracts/ # OpenZeppelin Solidity library (submodule)
├─ src/
│  ├─ reentrancy/
│  │  ├─ VulnerableVault.sol
│  │  ├─ ReentrancyAttacker.sol
│  │  └─ FixedVault.sol
│  ├─ access-control/
│  │  ├─ VulnerableTreasury.sol
│  │  └─ FixedTreasury.sol
│  ├─ oracle-manipulation/
│  │  ├─ SimpleAMM.sol
│  │  ├─ VulnerableLending.sol
│  │  ├─ TWAPOracle.sol
│  │  └─ FixedLending.sol
│  └─ signature-replay/
│     ├─ VulnerableAirdrop.sol
│     └─ FixedAirdrop.sol
├─ test/
│  ├─ reentrancy/
│  │  └─ ReentrancyPoC.t.sol
│  ├─ access-control/
│  │  └─ AccessControlPoC.t.sol
│  ├─ oracle-manipulation/
│  │  └─ OracleManipulationPoC.t.sol
│  └─ signature-replay/
│     └─ SignatureReplayPoC.t.sol
└─ reports/
   ├─ 01-reentrancy.md
   ├─ 02-access-control.md
   └─ 03-signature-replay.md
```

## Dependencies

- [Foundry](https://book.getfoundry.sh)
- [forge-std](https://github.com/foundry-rs/forge-std) `v1.16.1` — Foundry standard testing library
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) `v5.6.1` — battle-tested Solidity components used in fixed versions (Ownable, ReentrancyGuard, ECDSA, etc.)

All dependencies are installed as git submodules under `lib/` and locked in `foundry.lock`.

## Getting Started

### 1. Install Foundry

Follow the official installation guide for your OS:
https://book.getfoundry.sh/getting-started/installation

Quick reference:

```bash
# macOS / Linux / WSL
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

```powershell
# Windows (PowerShell)
powershell -c "irm https://foundry.paradigm.xyz/install.ps1 | iex"
foundryup
```

### 2. Clone with submodules

```bash
git clone --recurse-submodules https://github.com/huichain/smart-contract-security-lab.git
cd smart-contract-security-lab
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
```

### 3. Build

```bash
forge build
```

### 4. Test

The lab currently ships with **15 passing tests** across three complete modules plus the in-progress Oracle Manipulation module.

**Reentrancy** (`test/reentrancy/`):

- `testExploit_DrainsVault` — proves the attacker drains a 10 ETH vault with 1 ETH of capital.
- `testFix_BlocksReentrancy` — proves the same exploit reverts against `FixedVault`.
- `testFix_AllowsHonestWithdraw` — sanity check that legitimate users still work.

**Access Control** (`test/access-control/`):

- `testExploit_AnyoneCanDrainTreasury` — proves anyone can drain the treasury via `withdraw`.
- `testExploit_AnyoneCanBecomeOwner` — proves anyone can seize ownership via `setOwner`.
- `testFix_BlocksUnauthorizedWithdraw` — proves `FixedTreasury` blocks unauthorized withdrawals.
- `testFix_BlocksUnauthorizedSetOwner` — proves unauthorized ownership transfer reverts.
- `testFix_AllowsOwnerFunctions` — sanity check that the owner can still operate the treasury.

**Signature Replay** (`test/signature-replay/`):

- `testExploit_SameSignatureClaimsTwice` — proves the same signature can be replayed to claim twice.
- `testFix_BlocksSignatureReplay` — proves nonce consumption blocks replaying the same signature.
- `testFix_RejectsExpiredSignature` — proves signatures cannot be used after their deadline.

**Oracle Manipulation** (`test/oracle-manipulation/`):

- `testExploit_SpotPriceManipulationInflatesBorrowLimit` — proves AMM spot-price manipulation inflates borrowing power.
- `testNormalPriceOnlyAllowsLimitedBorrow` — proves the unmanipulated price enforces the expected lower borrow limit.
- `testFix_BlocksSpotPriceManipulation` — proves TWAP pricing blocks the same spot-price manipulation attack.
- `testFix_AllowsHonestBorrow` — proves legitimate users can still borrow against the TWAP price.

Run all tests:

```bash
forge test
```

Run a single module:

```bash
forge test --match-path test/access-control/AccessControlPoC.t.sol -vv
```

> Note: `verbosity = 3` is set in `foundry.toml`, so `forge test` already shows the same level of detail as `forge test -vvv`.

## Roadmap (high-level)

| Vulnerability | Status |
| --- | --- |
| Reentrancy | ✅ Done — vulnerable + attacker + fix + tests + writeup |
| Access Control | ✅ Done — vulnerable + fix + tests + writeup |
| Signature Replay | ✅ Done — vulnerable + fixed airdrop + tests + writeup |
| Oracle Manipulation | 🟡 In progress — vulnerable + TWAP fix + tests; writeup pending |
| Upgradeable Proxy | ⚪ Planned |

## About the Author

Software engineer with C++ / C# background, transitioning into smart contract security and Web3 tooling.

- GitHub: [huichain](https://github.com/huichain)
- X: [@vividhui](https://x.com/vividhui)
