# Smart Contract Security Lab

A Foundry-based lab to learn smart contract security by reproducing real vulnerabilities, writing PoCs, and proposing fixes.

This repo is built **day by day**, not all at once.  
Each day adds one small, working piece: a vulnerable contract, an attacker, a fix, or a report.

## Status

In progress. Started on Day 1.

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

## Project Structure

```text
smart-contract-security-lab/
├─ foundry.toml         # Foundry config + remappings
├─ foundry.lock         # Locked dependency versions
├─ .gitmodules          # Git submodules (forge-std, openzeppelin-contracts)
├─ .gitignore
├─ README.md
├─ lib/
│  ├─ forge-std/             # Foundry standard testing library (submodule)
│  └─ openzeppelin-contracts/ # OpenZeppelin Solidity library (submodule)
├─ src/
│  └─ reentrancy/
│     ├─ VulnerableVault.sol
│     ├─ ReentrancyAttacker.sol
│     └─ FixedVault.sol
├─ test/
│  └─ reentrancy/
│     └─ ReentrancyPoC.t.sol
└─ reports/
   └─ 01-reentrancy.md
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

No tests yet — tests will be added starting from Day 2.

```bash
forge test
```

> Note: `verbosity = 3` is set in `foundry.toml`, so `forge test` already shows the same level of detail as `forge test -vvv`.

## Roadmap (high-level)

| Vulnerability | Status |
| --- | --- |
| Reentrancy | ✅ Done — vulnerable + attacker + fix + tests + writeup |
| Access Control | Planned |
| Signature Replay | Planned |
| Oracle Manipulation | Planned |
| Upgradeable Proxy | Planned |

## About the Author

Software engineer with C++ / C# background, transitioning into smart contract security and Web3 tooling.

- GitHub: [huichain](https://github.com/huichain)
- X: [@vividhui](https://x.com/vividhui)
