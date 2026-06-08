# 04 — Oracle Manipulation in `VulnerableLending`

## Title

Using an AMM spot price as the lending oracle allows an attacker to inflate `maxBorrow` and drain the debt-asset pool.

## Metadata

| | |
| --- | --- |
| **Severity** | High |
| **Difficulty** | Medium |
| **Type** | Oracle Manipulation / Economic |
| **Target** | `src/oracle-manipulation/VulnerableLending.sol` |
| **Finding ID** | SCSL-ORACLE-01 |

## Severity Rationale

Rated **High** because a single attacker can borrow the entire lending pool after depositing a modest amount of collateral. No privileged role is required; the attacker only needs enough debt asset to move the AMM reserves within the same transaction (on mainnet this is typically funded by a flash loan).

Difficulty is rated **Medium**: the exploit is a well-known DeFi pattern (spot-price oracle manipulation, as in the 2020 bZx incidents), but it requires understanding AMM reserve math and, in production, atomic flash-loan plumbing.

Severity tiers used in this lab (aligned with common audit firm conventions):

| Severity | Description |
| --- | --- |
| Critical | Catastrophic financial loss or complete protocol takeover. |
| High | Significant financial loss or core functionality break. |
| Medium | Real impact but requires specific conditions. |
| Low | Limited impact, hard to exploit, or only edge cases. |
| Informational | Best-practice / code quality issues. |

## Summary

`VulnerableLending` prices collateral with `SimpleAMM.getSpotPrice()`, which returns the instantaneous reserve ratio `debtAssetReserve / collateralReserve`. A large `swapDebtForCollateral` in the same block moves reserves and spikes the spot price immediately.

Because `maxBorrow` reads this spot price on every call, an attacker can deposit collateral, manipulate the AMM upward, and borrow far more debt asset than the honest LTV would allow. In the PoC, the attacker drains the full **1,000** unit pool even though the unmanipulated borrow cap was only **50**.

## Affected Code

`src/oracle-manipulation/VulnerableLending.sol`

```solidity
function maxBorrow(address account) public view returns (uint256) {
    uint256 collateralValue = (collateralDeposits[account] * oracle.getSpotPrice()) / PRICE_SCALE;
    return (collateralValue * LTV_BPS) / BPS;
}
```

`src/oracle-manipulation/SimpleAMM.sol`

```solidity
function getSpotPrice() external view returns (uint256) {
    return (debtAssetReserve * PRICE_SCALE) / collateralReserve;
}
```

The lending market treats a manipulable DEX spot quote as authoritative collateral pricing. There is no time averaging, liquidity check, or secondary oracle.

## Impact

With **100** units of collateral at 50% LTV and a fair spot price of **1**, the honest borrow cap is **50** debt units.

After swapping **9,000** debt asset into the AMM (reserves move from `1000:1000` to roughly `100:10000`), the spot price jumps to about **100**. The same **100** collateral is now valued at **10,000** debt units, so `maxBorrow` becomes **5,000** — enough to borrow the entire **1,000** unit pool.

| State | Spot price | Collateral value (100 units) | `maxBorrow` (50% LTV) |
| --- | --- | --- | --- |
| Before manipulation | 1 | 100 | 50 |
| After manipulation | ~100 | ~10,000 | ~5,000 |

In production this pattern can drain lending pools, mint unbacked stablecoins, or trigger unfair liquidations whenever a protocol uses a shallow AMM, single-block spot price, or on-chain reserve ratio as its sole oracle.

## Root Cause

**Spot price is not manipulation-resistant.**

`SimpleAMM` follows constant-product math (`x * y = k`). A single large trade changes reserves and therefore changes `getSpotPrice()` in the same transaction. `VulnerableLending` consults that value directly when computing `collateralValue` and `maxBorrow`.

The attack does not break Solidity arithmetic or access control. The protocol simply trusts a price source that an attacker can temporarily distort. On mainnet, flash loans make the capital requirement for the swap negligible as long as the manipulation and borrow happen atomically.

## Proof of Concept

Reproduce locally:

```bash
forge test --match-test testExploit_SpotPriceManipulationInflatesBorrowLimit -vvvv
```

Test file: `test/oracle-manipulation/OracleManipulationPoC.t.sol`

Attack flow:

1. Seed `VulnerableLending` with **1,000** debt-asset liquidity.
2. Attacker deposits **100** collateral. At spot price **1**, `maxBorrow` is **50**.
3. Attacker calls `amm.swapDebtForCollateral(9_000)`, spiking the spot price.
4. Attacker calls `lending.borrow(1_000)` and drains the pool.

The test omits flash-loan plumbing and uses virtual AMM reserves so the PoC stays focused on the oracle bug. On mainnet the swap capital would usually come from a flash loan repaid in the same transaction.

Verifying assertions (from the test):

```text
manipulatedPrice      > normalPrice
manipulatedMaxBorrow  > normalMaxBorrow
attacker debt balance == 1_000
pool liquidity        == 0
```

Sanity check — honest borrow cap without manipulation:

```bash
forge test --match-test testNormalPriceOnlyAllowsLimitedBorrow -vv
```

Borrowing `maxBorrow + 1` reverts with `insufficient collateral`.

## Recommendation

### Short term

Do not use an AMM spot price as the sole lending oracle. Price collateral with a **time-weighted average (TWAP)** over a meaningful window, or use an external manipulation-resistant feed (e.g. Chainlink) with sane staleness bounds.

This lab's fix replaces `getSpotPrice()` with `TWAPOracle.consult()`:

```solidity
function maxBorrow(address account) public view returns (uint256) {
    uint256 collateralValue = (collateralDeposits[account] * oracle.consult()) / PRICE_SCALE;
    return (collateralValue * LTV_BPS) / BPS;
}
```

`TWAPOracle` records cumulative prices via `update()` and returns the average over `minWindow` seconds (the PoC uses **1,800** seconds = 30 minutes). A single-block reserve spike therefore cannot instantly inflate `maxBorrow`.

### Long term

1. **Prefer robust oracle designs** — Chainlink, multiple sources, or TWAP with sufficient window length and observation frequency.
2. **Bound per-block price movement** — circuit breakers or maximum deviation checks between spot and TWAP.
3. **Use deep liquidity pools** — manipulation cost rises with liquidity, but spot-only pricing is never sufficient on its own.
4. **Add regression tests** — assert that a large same-block swap cannot increase `maxBorrow` beyond the honest LTV cap. See `testFix_BlocksSpotPriceManipulation`.
5. **Document oracle assumptions** — if a precompile, DEX, or external API is used, specify which fields are read and which liabilities are subtracted (see Monetrix M-01: counting supply without borrow).

## Fixed Implementation

| File | Role |
| --- | --- |
| `src/oracle-manipulation/TWAPOracle.sol` | Records cumulative AMM prices; `consult()` returns TWAP over `minWindow`. |
| `src/oracle-manipulation/FixedLending.sol` | Same lending logic as `VulnerableLending`, but uses `oracle.consult()`. |

Verification tests in `test/oracle-manipulation/OracleManipulationPoC.t.sol`:

| Test | Asserts |
| --- | --- |
| `testExploit_SpotPriceManipulationInflatesBorrowLimit` | Vulnerable lending: spot manipulation inflates borrow limit and drains the pool. |
| `testNormalPriceOnlyAllowsLimitedBorrow` | Without manipulation, LTV caps borrowing at **50**. |
| `testFix_BlocksSpotPriceManipulation` | After the same swap, spot spikes above TWAP but borrowing the full pool reverts; liquidity remains. |
| `testFix_AllowsHonestBorrow` | Legitimate users can still borrow **50** against stable TWAP pricing. |

Run the oracle manipulation suite:

```bash
forge test --match-path test/oracle-manipulation/OracleManipulationPoC.t.sol -vv
```

Expected output:

```text
[PASS] testExploit_SpotPriceManipulationInflatesBorrowLimit() (gas: 110349)
[PASS] testFix_AllowsHonestBorrow()                   (gas: 1247803)
[PASS] testFix_BlocksSpotPriceManipulation()          (gas: 1205321)
[PASS] testNormalPriceOnlyAllowsLimitedBorrow()         (gas: 50887)
```

Run all lab tests:

```bash
forge test
```

Expected result:

```text
15 tests passed, 0 failed
```

## Notes and Learnings

- **Spot ≠ safe oracle.** Any price derived from current DEX reserves can be moved by a sufficiently large swap in the same transaction.
- **Flash loans amplify economic attacks.** They are not the root cause; the root cause is trusting a manipulable price source for collateral valuation.
- **TWAP reduces single-block manipulation.** It does not eliminate oracle risk entirely — keepers must call `update()`, window length matters, and very thin pools can still be distorted over time.
- **Historical reference.** The February 2020 bZx attacks exploited similar price-source inconsistencies between Uniswap spot prices and lending protocol accounting, using flash-loan capital to amplify the manipulation.
- **Related real-world pattern.** Monetrix M-01 (Code4rena, 2026) is a different flavor of the same lesson: protocol accounting used an incomplete external balance (supply without borrow), producing phantom surplus. Both cases are "the number used for settlement was wrong."
