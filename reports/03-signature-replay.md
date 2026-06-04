# 03 — Signature Replay in `VulnerableAirdrop`

## Title

Missing replay protection in `VulnerableAirdrop.claim` allows the same signed authorization to be reused multiple times.

## Metadata

| | |
| --- | --- |
| **Severity** | High |
| **Difficulty** | Low |
| **Type** | Signature Replay / Authorization |
| **Target** | `src/signature-replay/VulnerableAirdrop.sol` |
| **Finding ID** | SCSL-SR-01 |

## Severity Rationale

Rated **High** because a valid signature authorizing one ETH claim can be reused until the airdrop pool is drained. The attacker does not need to compromise the trusted signer or break ECDSA; they only need to obtain one valid signature for their own address.

Difficulty is rated **Low**: exploitation is a normal external call repeated with the same calldata. No custom attacker contract, flash loan, callback, or privileged access is required.

Severity tiers used in this lab (aligned with common audit firm conventions):

| Severity | Description |
| --- | --- |
| Critical | Catastrophic financial loss or complete protocol takeover. |
| High | Significant financial loss or core functionality break. |
| Medium | Real impact but requires specific conditions. |
| Low | Limited impact, hard to exploit, or only edge cases. |
| Informational | Best-practice / code quality issues. |

## Summary

`VulnerableAirdrop` verifies that `TRUSTED_SIGNER` signed a claim for `(account, amount)`, but the signed message does not include a nonce, deadline, chain id, or contract address. After a successful claim, the contract also does not mark the signature as used.

As a result, the same valid signature remains valid forever and can be replayed repeatedly by the same claimant.

## Affected Code

`src/signature-replay/VulnerableAirdrop.sol`

```solidity
function claim(uint256 amount, bytes calldata signature) external {
    require(amount > 0, "zero amount");
    require(address(this).balance >= amount, "insufficient airdrop balance");

    bytes32 digest = getClaimDigest(msg.sender, amount);
    address recovered = digest.recover(signature);
    require(recovered == TRUSTED_SIGNER, "invalid signature");

    (bool ok, ) = payable(msg.sender).call{value: amount}("");
    require(ok, "ETH transfer failed");

    emit Claimed(msg.sender, amount);
}
```

```solidity
function getClaimDigest(address account, uint256 amount) public pure returns (bytes32) {
    bytes32 messageHash = keccak256(abi.encodePacked(account, amount));
    return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
}
```

The digest only commits to `account` and `amount`. It intentionally excludes:

1. `nonce` or used-signature tracking.
2. `deadline` or expiry.
3. `block.chainid`.
4. `address(this)`.

## Impact

A claimant with one valid signature for `1 ether` can claim `1 ether` multiple times. In the PoC, the claimant uses the same signature twice and receives `2 ether` total, even though the trusted signer only authorized one `1 ether` claim.

In production, this pattern can drain an airdrop pool, rewards contract, claim portal, or any protocol function that treats an off-chain signature as authorization without consuming it.

The issue is especially dangerous because the signature is valid according to ECDSA. The bug is not in cryptography; it is in the missing replay protection around the signed message.

## Root Cause

The signed authorization is not unique per claim.

`getClaimDigest(account, amount)` returns the same digest every time the same account and amount are used. Since `claim` does not update any state tied to that digest, the recovered signer remains `TRUSTED_SIGNER` on every replay.

The missing fields each create a separate replay surface:

1. **No nonce** — the same user can reuse the same signature in the same contract.
2. **No deadline** — an old signature never expires.
3. **No contract address** — a signature may be reusable on another contract with the same digest format.
4. **No chain id** — a signature may be reusable across chains if the same contract logic exists elsewhere.

## Proof of Concept

Reproduce locally:

```bash
forge test --match-test testExploit_SameSignatureClaimsTwice -vvv
```

Test file: `test/signature-replay/SignatureReplayPoC.t.sol`

Attack flow:

1. `TRUSTED_SIGNER` signs a digest for `(claimant, 1 ether)`.
2. `claimant` calls `VulnerableAirdrop.claim(1 ether, signature)`.
3. The contract recovers `TRUSTED_SIGNER` and transfers `1 ether`.
4. `claimant` calls `claim` again with the exact same `signature`.
5. The digest is unchanged, the recovered signer is still valid, and another `1 ether` is transferred.

Verifying assertions:

```text
claimant.balance         == 2 ether
address(airdrop).balance == AIRDROP_POOL - 2 ether
```

## Recommendation

### Short term

Bind the signed message to the exact claim context and consume the user's nonce after a successful claim.

The fixed digest should include:

1. `address(this)` — binds the signature to this contract.
2. `block.chainid` — binds the signature to this chain.
3. `account` — binds the claim to the recipient.
4. `amount` — binds the authorized amount.
5. `nonce` — makes each claim unique and single-use.
6. `deadline` — prevents old signatures from being valid forever.

```solidity
bytes32 messageHash = keccak256(
    abi.encodePacked(
        address(this),
        block.chainid,
        account,
        amount,
        nonce,
        deadline
    )
);
```

Then consume the nonce before the ETH transfer:

```solidity
uint256 nonce = nonces[msg.sender];
bytes32 digest = getClaimDigest(msg.sender, amount, nonce, deadline);
address recovered = digest.recover(signature);
require(recovered == TRUSTED_SIGNER, "invalid signature");

nonces[msg.sender] = nonce + 1;
```

### Long term

1. Prefer **EIP-712 typed structured data** for production signature schemes. It improves wallet UX and makes domain separation explicit.
2. Add replay tests for every signature-based flow: same signature twice, expired signature, wrong signer, wrong chain/domain, and wrong amount.
3. Document exactly what the trusted signer is authorizing and which fields must be included in the digest.
4. Treat nonce consumption as part of the authorization invariant: if a signed action succeeds, the authorization must be unusable afterward.

## Fixed Implementation

`src/signature-replay/FixedAirdrop.sol` adds per-user nonces, expiry deadlines, and domain binding.

Verification tests in `test/signature-replay/SignatureReplayPoC.t.sol`:

| Test | Asserts |
| --- | --- |
| `testExploit_SameSignatureClaimsTwice` | Vulnerable contract: the same signature can claim twice. |
| `testFix_BlocksSignatureReplay` | Fixed contract: the first claim succeeds, consumes the nonce, and replaying the same signature reverts with `invalid signature`. |
| `testFix_RejectsExpiredSignature` | Fixed contract: a signature past its deadline reverts with `signature expired`. |

Run the signature replay suite:

```bash
forge test --match-path test/signature-replay/SignatureReplayPoC.t.sol -vv
```

Expected output:

```text
[PASS] testExploit_SameSignatureClaimsTwice()
[PASS] testFix_BlocksSignatureReplay()
[PASS] testFix_RejectsExpiredSignature()
```

Run all lab tests:

```bash
forge test
```

Expected result:

```text
11 tests passed, 0 failed
```

## Notes and Learnings

- **ECDSA verification is not enough.** A signature can be cryptographically valid and still be unsafe if the signed message omits replay protection.
- **Nonce is the key replay guard.** In Solidity, `mapping(address => uint256)` defaults to `0`, so a user's first expected nonce is `0`; each successful claim increments it.
- **Domain separation matters.** `address(this)` and `block.chainid` prevent a signature intended for one contract or chain from being reused elsewhere.
- **Deadline limits damage window.** Even if a signature leaks, it should not remain valid forever.
- **This lab uses personal-sign style hashing for simplicity.** Production systems should usually use EIP-712 for clearer typed messages and better wallet display.
