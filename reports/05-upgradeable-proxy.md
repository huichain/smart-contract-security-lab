# 05 — Unprotected Initializer in Upgradeable Proxy Storage

## Title

Unprotected `initialize()` behind a `delegatecall` proxy allows anyone to seize or overwrite `owner` in proxy storage.

## Metadata

| | |
| --- | --- |
| **Severity** | High |
| **Difficulty** | Low |
| **Type** | Access Control / Initialization |
| **Target** | `src/upgradeable-proxy/ImplementationV1.sol` (via `SimpleProxy`) |
| **Finding ID** | SCSL-PROXY-01 |

## Severity Rationale

Rated **High** because any external account can become `owner` of the proxy's storage and invoke owner-only functions such as `setValue`. In a production vault this maps to full protocol takeover (fund movement, parameter changes, upgrades) without exploiting unrelated bugs.

Difficulty is rated **Low**: the pattern is well documented in upgradeable-contract guidance, public incidents involve unprotected initializers, and the PoC is a single unprivileged call through the proxy address.

Severity tiers used in this lab (aligned with common audit firm conventions):

| Severity | Description |
| --- | --- |
| Critical | Catastrophic financial loss or complete protocol takeover. |
| High | Significant financial loss or core functionality break. |
| Medium | Real impact but requires specific conditions. |
| Low | Limited impact, hard to exploit, or only edge cases. |
| Informational | Best-practice / code quality issues. |

## Summary

`ImplementationV1` is designed to run behind `SimpleProxy` using `delegatecall`. Users interact with the proxy address, but state (`owner`, `value`) is stored in the proxy's storage slots.

The vulnerable `initialize(address owner_)` function is `external`, has no access control, and can be called more than once. An attacker can either front-run the legitimate deployer and call `initialize(attacker)` first, or wait until after the admin initializes and call `initialize(attacker)` again to overwrite `owner`.

Once `owner` points to the attacker, `setValue` and any other owner-gated logic on the proxy address execute under attacker control.

## Background: Why Proxies Need `initialize`

Upgradeable systems split **code** (implementation contract) from **state** (proxy contract):

```text
User → SimpleProxy.fallback → delegatecall → ImplementationV1 logic
State (owner, value) lives in proxy storage, not implementation storage
```

Constructors run only when the implementation contract is deployed. They do **not** execute when users call the proxy. Therefore privileged setup must happen in a separate `initialize` function called on the **proxy address** after deployment.

If `initialize` is public and not one-time, it becomes an unguarded write to the most sensitive storage slots in the system.

`SimpleProxy` stores its implementation pointer in the EIP-1967 slot so it does not collide with `owner` at slot 0 in the logic contract layout.

## Affected Code

`src/upgradeable-proxy/ImplementationV1.sol`

```solidity
function initialize(address owner_) external {
    owner = owner_;
    emit Initialized(owner_);
}
```

There is no:

- `initializer` / one-time guard,
- check that `msg.sender` is allowed to perform setup,
- `_disableInitializers()` on the implementation to block direct initialization of the logic contract address.

`src/upgradeable-proxy/SimpleProxy.sol` forwards arbitrary calls:

```solidity
fallback() external payable {
    _delegate(_getImplementation());
}
```

So any caller can reach `initialize` through the proxy.

## Impact

| Attack | Result |
| --- | --- |
| Front-run initialization | Attacker becomes `owner` before the admin; admin's later `initialize` either overwrites or fails depending on ordering — with `ImplementationV1`, either party can win the race because there is no one-time guard. |
| Re-initialization | Admin initializes correctly; attacker later calls `initialize(attacker)` and overwrites `owner`. Admin loses `setValue` and any other owner powers. |

In the PoC, the attacker sets `value` to **1337** after seizing ownership. In production, the same bug on a treasury, vault, or governance module equals **full administrative takeover**.

## Root Cause

**Missing initialization hardening in an upgradeable logic contract.**

1. **No one-time initializer.** `initialize` can run arbitrarily many times, so `owner` can be replaced at any point.
2. **No authorized initializer.** Any `msg.sender` may call `initialize`; there is no deployer-only or factory-only gate.
3. **Implementation left initializable.** Without `_disableInitializers()` in the logic contract constructor, the implementation address itself can also be initialized, confusing monitoring and tooling (fixed in `FixedImplementationV1`).

This is the same class of bug as unprotected `init` functions in proxy-based systems and parallels Access Control findings where privileged state can be written by arbitrary callers.

## Proof of Concept

Reproduce locally:

```bash
forge test --match-test testExploit_UnprotectedInitializeLetsAttackerTakeOwnership -vvvv
forge test --match-test testExploit_AttackerCanReinitializeAndOverwriteOwner -vvvv
```

Test file: `test/upgradeable-proxy/ProxyPoC.t.sol`

### PoC #1 — front-run initialization

1. Deploy `ImplementationV1` and `SimpleProxy`.
2. Cast the proxy address to `ImplementationV1`.
3. Attacker calls `vault.initialize(attacker)` through the proxy.
4. Attacker calls `setValue(1337)`.

Verifying assertions:

```text
vault.owner() == attacker
vault.value()  == 1337
```

### PoC #2 — overwrite admin after honest setup

1. Admin calls `initialize(admin)` and `setValue(100)`.
2. Attacker calls `initialize(attacker)`.
3. `owner` becomes attacker; admin's `setValue(200)` reverts with `not owner`.

## Recommendation

### Short term

1. **Protect `initialize` with OpenZeppelin `Initializable` and the `initializer` modifier** so it succeeds only once per proxy instance.
2. **Call `_disableInitializers()` in the implementation constructor** so the bare logic contract cannot be initialized directly.
3. **Reject zero admin** — `require(owner_ != address(0))` to avoid bricking ownership.
4. **Initialize atomically in deployment scripts** — deploy proxy, then call `initialize` in the same transaction (or via a factory) to reduce front-running windows.

Example fix (this lab's `FixedImplementationV1`):

```solidity
constructor() {
    _disableInitializers();
}

function initialize(address owner_) external initializer {
    require(owner_ != address(0), "zero owner");
    owner = owner_;
    emit Initialized(owner_);
}
```

### Long term

1. Use audited proxy patterns — UUPS, Transparent Proxy, or OpenZeppelin Upgrades plugins — instead of a hand-rolled proxy for production.
2. Restrict `upgradeTo` with `onlyOwner` / timelock (this lab's `SimpleProxy.upgradeTo` is intentionally unguarded for teaching).
3. Add storage gaps and documented layout for `V2` upgrades; validate with `forge inspect` / upgrade safety checks to avoid storage collisions.
4. Add regression tests that assert replayed `initialize` reverts. See `testFix_BlocksReinitialize`.
5. Consider an initialization registry or factory that is the sole address allowed to call `initialize` if deployer EOA front-running is a concern.

## Fixed Implementation

| File | Role |
| --- | --- |
| `src/upgradeable-proxy/FixedImplementationV1.sol` | Same interface as `ImplementationV1`, but uses `Initializable`, `initializer`, and `_disableInitializers()`. |

Verification tests in `test/upgradeable-proxy/ProxyPoC.t.sol`:

| Test | Asserts |
| --- | --- |
| `testExploit_UnprotectedInitializeLetsAttackerTakeOwnership` | Vulnerable version: attacker seizes `owner` via proxy. |
| `testExploit_AttackerCanReinitializeAndOverwriteOwner` | Vulnerable version: attacker overwrites admin's ownership. |
| `testFix_BlocksReinitialize` | Fixed version: replayed `initialize` reverts; admin keeps control. |
| `testFix_AllowsLegitimateInit` | Fixed version: honest admin init and `setValue` still work. |
| `testFix_BlocksDirectInitializeOnImplementation` | Fixed version: logic contract address cannot be initialized directly. |

Run the upgradeable proxy suite:

```bash
forge test --match-path test/upgradeable-proxy/ProxyPoC.t.sol -vv
```

Expected output:

```text
[PASS] testExploit_AttackerCanReinitializeAndOverwriteOwner() (gas: 378920)
[PASS] testExploit_UnprotectedInitializeLetsAttackerTakeOwnership() (gas: 366879)
[PASS] testFix_AllowsLegitimateInit() (gas: 478135)
[PASS] testFix_BlocksDirectInitializeOnImplementation() (gas: 232070)
[PASS] testFix_BlocksReinitialize() (gas: 489740)
```

Run all lab tests:

```bash
forge test
```

Expected result:

```text
20 tests passed, 0 failed
```

## Notes and Learnings

- **`delegatecall` reuses proxy storage.** Always ask: "Who can write the first value into privileged slots?"
- **Constructors ≠ proxy setup.** Code in a constructor never runs at the proxy address; use `initialize` with strict guards.
- **One-time initialization is mandatory** for `owner`, oracle, pauser, and other admin roles in upgradeable contracts.
- **`_disableInitializers()` on the implementation** prevents a duplicate "initialized" logic contract from confusing integrators and tools.
- **Related real-world pattern.** SukukFi H-01 (unauthorized `withdraw` on ERC-4626-style vaults) is a different surface — missing `msg.sender` authorization — but the lesson is the same: privileged operations must validate the caller. Initialization is the setup-time variant of that mistake.
- **Optional follow-up in this lab.** Storage layout collisions when upgrading from `V1` to `V2`, and unprotected `upgradeTo`, are separate teaching topics not covered by this report.
