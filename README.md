# Smart Contract Security Lab

A Foundry-based lab to learn smart contract security by reproducing real vulnerabilities, writing PoCs, and proposing fixes.

This repo is built **day by day**, not all at once.  
Each day adds one small, working piece: a vulnerable contract, an attacker, a fix, or a report.

## Status

- ✅ **Reentrancy** module complete — vulnerable contract, attacker, fix, 3 passing tests, audit-style writeup
- ✅ **Access Control** module complete — vulnerable + fixed contracts, 5 passing tests, audit-style writeup
- 🟡 **Signature Replay** module started — vulnerable airdrop contract compiles; PoC, fix, and writeup next
- ⚪ Oracle Manipulation, Upgradeable Proxy — planned

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

## Signature Replay — Vulnerable Airdrop

- [x] `src/signature-replay/VulnerableAirdrop.sol`
  A deliberately vulnerable ETH airdrop that accepts an off-chain signature from a trusted signer, but the signed message only binds `account` and `amount`.
- [ ] `test/signature-replay/SignatureReplayPoC.t.sol`
  Planned PoC test: reuse the exact same signature twice and prove the claimant receives the airdrop twice.
- [ ] `src/signature-replay/FixedAirdrop.sol`
  Planned fix: bind signatures to nonce, deadline, chain id, and `address(this)`.
- [ ] `reports/03-signature-replay.md`
  Planned audit-style writeup covering replay impact, root cause, PoC, and mitigation.

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
│  └─ signature-replay/
│     └─ VulnerableAirdrop.sol
├─ test/
│  ├─ reentrancy/
│  │  └─ ReentrancyPoC.t.sol
│  └─ access-control/
│     └─ AccessControlPoC.t.sol
└─ reports/
   ├─ 01-reentrancy.md
   └─ 02-access-control.md
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

The lab currently ships with **8 passing tests** across two complete modules. The Signature Replay module has started with a vulnerable contract and will add tests next.

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
| Signature Replay | 🟡 In progress — vulnerable airdrop contract added |
| Oracle Manipulation | ⚪ Planned |
| Upgradeable Proxy | ⚪ Planned |

## About the Author

Software engineer with C++ / C# background, transitioning into smart contract security and Web3 tooling.

- GitHub: [huichain](https://github.com/huichain)
- X: [@vividhui](https://x.com/vividhui)
