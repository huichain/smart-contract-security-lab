# 01 — Reentrancy in `VulnerableVault.withdraw`

## Title

Reentrancy in `VulnerableVault.withdraw` allows an attacker to drain the vault with minimal capital.

## Severity

**High** — direct financial loss, exploitable by any user able to deploy a contract.

## Summary

`VulnerableVault.withdraw` sends ETH to `msg.sender` via a low-level `call` **before** updating the user's recorded balance. If `msg.sender` is a contract, its `receive()` function executes synchronously during the call, and can re-enter `withdraw` while the stale balance still passes the `require` check. The attacker contract uses this to repeatedly drain the vault until it is empty.

## Affected Code

`src/reentrancy/VulnerableVault.sol`

```solidity
function withdraw(uint256 amount) external {
    require(balances[msg.sender] >= amount, "insufficient balance");

    // External call happens BEFORE state update.
    (bool ok, ) = payable(msg.sender).call{value: amount}("");
    require(ok, "ETH transfer failed");

    // State update happens AFTER — too late.
    balances[msg.sender] = 0;
}
```

## Impact

With **1 ETH** of attacker capital, the attacker drains a **10 ETH** vault to zero. The exploit re-enters `withdraw` **11 times** before the state-update line ever runs. More generally, an attacker contract can take all ETH held by the vault on top of recovering its own deposit.

In production this pattern can drain protocol treasuries, vaults, or any contract that:

1. Holds ETH on behalf of users.
2. Sends ETH via `.call{value: ...}("")` to user-controlled addresses.
3. Updates internal accounting after the external call.

## Root Cause

The function violates the **Checks-Effects-Interactions** pattern.

In the EVM, calling `payable(msg.sender).call{value: amount}("")` is a **synchronous** transfer of control: the receiver's `receive()` or `fallback()` runs to completion before `withdraw` resumes its next line. If the receiver is a contract, it can re-enter `withdraw` while:

- ETH has already left the vault,
- but `balances[msg.sender]` is still equal to the original deposit.

Every nested call therefore passes the same `require(balances[msg.sender] >= amount)` check and triggers another transfer. Once the vault runs out of ETH, the stack unwinds and `balances[msg.sender] = 0` finally executes — by then the funds are gone.

## Proof of Concept

Reproduce locally:

```bash
forge test --match-test testExploit_DrainsVault -vvvv
```

Test file: `test/reentrancy/ReentrancyPoC.t.sol`
Attacker contract: `src/reentrancy/ReentrancyAttacker.sol`

Attack flow:

1. Victim deposits 10 ETH into `VulnerableVault`.
2. Attacker deploys `ReentrancyAttacker` and calls `attack{value: 1 ether}()`.
3. `attack()` first calls `vault.deposit{value: 1 ether}()` so the attacker has a recorded balance.
4. `attack()` calls `vault.withdraw(1 ether)`.
5. Vault sends 1 ETH to the attacker contract; the attacker's `receive()` executes.
6. `receive()` calls `vault.withdraw(1 ether)` again — the balance check still passes.
7. Steps 5–6 repeat **11 times** until the vault has 0 ETH.
8. The recursion unwinds and `balances[attacker] = 0` finally executes — funds are already gone.

Verifying assertions (from the test):

```text
address(vault).balance       == 0
address(attacker).balance    == 11 ether  (10 from victim + 1 own deposit)
```

## Recommendation

Apply Checks-Effects-Interactions: update state **before** any external call.

```solidity
function withdraw(uint256 amount) external nonReentrant {
    require(balances[msg.sender] >= amount, "insufficient balance");

    // Effect first.
    balances[msg.sender] -= amount;

    // Interaction last.
    (bool ok, ) = payable(msg.sender).call{value: amount}("");
    require(ok, "ETH transfer failed");
}
```

For defense in depth, also add OpenZeppelin's `ReentrancyGuard`:

```solidity
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FixedVault is ReentrancyGuard {
    // ...
}
```

The two protections are independent:

- **CEI** makes the re-entrancy benign: the second call sees a debited balance and the `require` rejects it.
- **`nonReentrant`** prevents the second call from running at all.

Combined, the contract is robust even if a future refactor accidentally breaks one of the two.

## Fixed Implementation

`src/reentrancy/FixedVault.sol` applies both protections.

Verification tests in `test/reentrancy/ReentrancyPoC.t.sol`:

| Test | Asserts |
| --- | --- |
| `testFix_BlocksReentrancy` | The same attacker, same flow against `FixedVault`, reverts. Vault keeps the victim's 10 ETH; attacker contract balance is 0. |
| `testFix_AllowsHonestWithdraw` | A legitimate user can deposit and withdraw normally — the fix does not break the happy path. |

Run all tests:

```bash
forge test
```

Expected output:

```text
[PASS] testExploit_DrainsVault()        (gas: 172017)
[PASS] testFix_AllowsHonestWithdraw()   (gas: 303854)
[PASS] testFix_BlocksReentrancy()       (gas: 553056)
```

## Notes and Learnings

- **Solidity ≥ 0.8 caveat.** This demo uses `balances[msg.sender] = 0` (full reset) rather than `-= amount`. With `-=` and the default arithmetic checks of 0.8.x, the second re-entry would underflow-revert before the canonical drain pattern could play out. Setting to `0` is what makes the textbook reentrancy reproducible on a modern compiler. The core lesson — *external call before state update is unsafe* — is independent of the arithmetic style.
- **Synchronous control transfer.** Re-entrancy is possible because EVM calls are synchronous; there is no event loop or scheduler. Every call halts the caller until the callee returns or reverts.
- **`nonReentrant` is not a substitute for CEI.** It is a defense in depth. CEI alone is sufficient to prevent the classic pattern shown here.
- **Historical reference.** The DAO hack (2016) was caused by the same pattern and lost approximately $60M of ETH.
