# 02 — Missing Access Control in `VulnerableTreasury`

## Title

Missing access control on `VulnerableTreasury.withdraw` and `VulnerableTreasury.setOwner` allows any account to drain funds or seize ownership.

## Metadata

| | |
| --- | --- |
| **Severity** | High (withdraw) / Critical (setOwner) |
| **Difficulty** | Low |
| **Type** | Access Control |
| **Target** | `src/access-control/VulnerableTreasury.sol` |
| **Finding IDs** | SCSL-AC-01 (`withdraw`), SCSL-AC-02 (`setOwner`) |

## Severity Rationale

**SCSL-AC-01 — `withdraw` (High):** Any external account can transfer all ETH held by the treasury to an arbitrary address. No role, deposit, or prior interaction is required beyond calling a public function. Impact is direct and total loss of treasury funds.

**SCSL-AC-02 — `setOwner` (Critical):** Any external account can overwrite the `owner` state variable in a single transaction. After takeover, the attacker controls all owner-gated logic (including `withdraw` once properly restricted, or any future admin functions). This is rated **Critical** because it enables permanent protocol/admin takeover, not only a one-time theft.

Difficulty is rated **Low** for both: exploitation is a single `call` from an EOA; no flash loans, callbacks, or custom attacker contracts are required.

Severity tiers used in this lab (aligned with common audit firm conventions):

| Severity | Description |
| --- | --- |
| Critical | Catastrophic financial loss or complete protocol takeover. |
| High | Significant financial loss or core functionality break. |
| Medium | Real impact but requires specific conditions. |
| Low | Limited impact, hard to exploit, or only edge cases. |
| Informational | Best-practice / code quality issues. |

## Summary

`VulnerableTreasury` stores an `owner` address set in the constructor, implying privileged administration of protocol funds. However, neither `withdraw` nor `setOwner` validates that `msg.sender` is the owner (or holds any role). The contract therefore exhibits **two independent** access-control failures:

1. **`withdraw`** — any account can move treasury ETH to any recipient.
2. **`setOwner`** — any account can assign themselves as owner, permanently capturing admin rights.

An attacker does not need to exploit both bugs to cause damage; either one is sufficient.

## Affected Code

`src/access-control/VulnerableTreasury.sol`

### Finding SCSL-AC-01 — Unrestricted `withdraw`

```solidity
function withdraw(address payable to, uint256 amount) external {
    require(to != address(0), "zero recipient");
    require(address(this).balance >= amount, "insufficient treasury balance");

    (bool ok, ) = to.call{value: amount}("");
    require(ok, "ETH transfer failed");

    emit Withdrawn(msg.sender, to, amount);
}
```

There is no `msg.sender == owner` check, no `onlyOwner` modifier, and no role-based guard.

### Finding SCSL-AC-02 — Unrestricted `setOwner`

```solidity
function setOwner(address newOwner) external {
    require(newOwner != address(0), "zero owner");

    address previousOwner = owner;
    owner = newOwner;

    emit OwnerChanged(previousOwner, newOwner);
}
```

The current `owner` is never consulted. Any caller can redirect ownership.

### Design smell

The contract **declares** `owner` but does not **enforce** it on sensitive paths — a common audit finding described as “role defined but not used” or “missing modifier on privileged function.”

## Impact

### SCSL-AC-01 — Fund drainage

A contributor deposits **10 ETH** into the treasury. An attacker calls `withdraw(attacker, 10 ether)` and receives the full balance. The treasury holds **0 ETH** afterward.

Unlike the reentrancy module, no attacker contract is required; a standard EOA suffices.

### SCSL-AC-02 — Ownership takeover

The legitimate deployer is `owner`. An attacker calls `setOwner(attacker)`. `treasury.owner()` now returns the attacker address. Even if `withdraw` were later patched without fixing `setOwner`, the attacker could front-run or the damage may already be done at takeover time.

In production, treasury contracts often gate upgrades, parameter changes, or emergency withdrawals behind `owner`. Seizing `owner` is equivalent to seizing the protocol admin key.

## Root Cause

Sensitive functions were implemented as `external` without authorization checks. The team added an `owner` field for documentation or future use but failed to wire it into the access-control layer.

Contributing factors:

1. **No shared base contract** — `Ownable`, `AccessControl`, or an internal `onlyOwner` modifier was not used consistently.
2. **No tests for negative paths** — tests may have covered “owner can withdraw” but not “non-owner must revert.”
3. **Copy-paste / incomplete refactor** — `owner` set in `constructor` suggests intent to restrict functions that was never applied.

## Proof of Concept

Reproduce locally:

```bash
# Drain treasury (SCSL-AC-01)
forge test --match-test testExploit_AnyoneCanDrainTreasury -vvv

# Seize ownership (SCSL-AC-02)
forge test --match-test testExploit_AnyoneCanBecomeOwner -vvv
```

Test file: `test/access-control/AccessControlPoC.t.sol`  
No separate attacker contract — exploits use `vm.prank(attackerEOA)` to simulate a real EOA.

### Attack flow — SCSL-AC-01

1. Contributor deposits 10 ETH via `deposit()`.
2. Attacker calls `withdraw(payable(attacker), 10 ether)`.
3. Treasury balance becomes `0`; attacker balance increases by `10 ether`.

Verifying assertions:

```text
address(treasury).balance == 0
attacker.balance         == 10 ether
```

### Attack flow — SCSL-AC-02

1. Treasury deployer is `owner` (e.g. test contract or multisig).
2. Attacker calls `setOwner(attacker)`.
3. `treasury.owner() == attacker`.

No ETH movement is required to complete this exploit.

## Recommendation

### Short term

1. Add `onlyOwner` (or equivalent) to **every** function that moves funds, changes roles, or updates critical configuration.
2. Prefer OpenZeppelin `Ownable` instead of a hand-rolled `owner` variable so checks cannot be forgotten on one function only.

```solidity
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract FixedTreasury is Ownable {
    constructor() Ownable(msg.sender) {}

    function withdraw(address payable to, uint256 amount) external onlyOwner {
        // ...
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero owner");
        transferOwnership(newOwner);
    }
}
```

Non-owners must revert. OpenZeppelin v5 uses the custom error `OwnableUnauthorizedAccount(address caller)`.

### Long term

1. **Use `Ownable2Step` for ownership transfer** in production treasuries so a mistyped address does not instantly hand control to the wrong party:

   ```solidity
   import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
   ```

2. **Prefer `AccessControl` + roles** when multiple privilege levels exist (operator, guardian, pauser) instead of a single `owner`.
3. **Negative-path tests** for every privileged function: assert unauthorized callers revert with the expected error selector.
4. **Checklist on review:** “Does this function mutate funds, roles, or implementation? If yes, document required role and enforce in code.”

`deposit` and `receive` may remain public if the design intentionally allows anyone to fund the treasury; document that choice explicitly in the report and NatSpec.

## Fixed Implementation

`src/access-control/FixedTreasury.sol` inherits OpenZeppelin `Ownable` and applies `onlyOwner` to `withdraw` and `setOwner`. `setOwner` delegates to `transferOwnership` for consistent ownership events and internal state.

Verification tests in `test/access-control/AccessControlPoC.t.sol`:

| Test | Asserts |
| --- | --- |
| `testExploit_AnyoneCanDrainTreasury` | Vulnerable contract: attacker drains 10 ETH. |
| `testExploit_AnyoneCanBecomeOwner` | Vulnerable contract: attacker becomes `owner`. |
| `testFix_BlocksUnauthorizedWithdraw` | `FixedTreasury`: attacker `withdraw` reverts with `OwnableUnauthorizedAccount`; balance unchanged. |
| `testFix_BlocksUnauthorizedSetOwner` | `FixedTreasury`: attacker `setOwner` reverts; `owner` unchanged. |
| `testFix_AllowsOwnerFunctions` | Owner can `withdraw` to a recipient and `setOwner` to a new address. |

Run all lab tests:

```bash
forge test
```

Expected output (access-control suite):

```text
[PASS] testExploit_AnyoneCanBecomeOwner()        (gas: ~19k)
[PASS] testExploit_AnyoneCanDrainTreasury()      (gas: ~48k)
[PASS] testFix_AllowsOwnerFunctions()            (gas: ~362k)
[PASS] testFix_BlocksUnauthorizedSetOwner()      (gas: ~316k)
[PASS] testFix_BlocksUnauthorizedWithdraw()      (gas: ~327k)
```

## Notes and Learnings

- **Two bugs, one contract.** Access-control reviews must enumerate *all* privileged surfaces. Fixing only `withdraw` while leaving `setOwner` open still allows full takeover.
- **EOA vs contract attacker.** Reentrancy often requires a malicious contract; missing access control does not. This lowers the exploitation bar.
- **`owner` without enforcement is worse than no `owner`.** It signals trust boundaries to integrators that do not exist in code.
- **Treasury vs vault naming.** This module models a protocol treasury (shared pool + admin withdrawal). The reentrancy module models per-user balances in a vault — different assets, same security discipline.
- **Production hardening.** Real deployments should combine `onlyOwner`, multisig owners, timelocks on large withdrawals, and `Ownable2Step` for ownership changes. This lab intentionally keeps the fix minimal to isolate the access-control lesson.
