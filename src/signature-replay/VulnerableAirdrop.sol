// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title  VulnerableAirdrop
/// @notice A deliberately vulnerable ETH airdrop used to demonstrate signature replay.
/// @dev    The trusted signer authorizes a user to claim `amount`, but the signed
///         message does not include replay protection or domain separation.
///
///         Vulnerabilities:
///
///         1. No nonce or used-signature tracking - the same signature can be reused.
///         2. No deadline - a valid signature never expires.
///         3. No chain id or contract address - the signature is not bound to one domain.
contract VulnerableAirdrop {
    using ECDSA for bytes32;

    address public immutable TRUSTED_SIGNER;

    event Funded(address indexed sender, uint256 amount);
    event Claimed(address indexed account, uint256 amount);

    constructor(address signer) {
        require(signer != address(0), "zero signer");
        TRUSTED_SIGNER = signer;
    }

    /// @notice Allow the airdrop pool to receive plain ETH funding.
    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }

    /// @notice Anyone may fund the airdrop pool.
    function fund() external payable {
        require(msg.value > 0, "zero funding");

        emit Funded(msg.sender, msg.value);
    }

    /// @notice Claims ETH using an off-chain signature from `TRUSTED_SIGNER`.
    /// @dev    Vulnerability: a valid signature for `(msg.sender, amount)` is not
    ///         consumed after use, so the caller can replay it until the pool is drained.
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

    /// @notice Returns the digest that `TRUSTED_SIGNER` must sign for this vulnerable version.
    /// @dev    Intentionally excludes nonce, deadline, chain id, and address(this).
    function getClaimDigest(address account, uint256 amount) public pure returns (bytes32) {
        bytes32 messageHash = keccak256(abi.encodePacked(account, amount));
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    }
}
