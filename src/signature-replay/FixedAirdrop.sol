// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title  FixedAirdrop
/// @notice A fixed ETH airdrop that prevents signature replay attacks.
/// @dev    The signed message is bound to this contract, this chain, the caller's
///         current nonce, and an expiry deadline.
contract FixedAirdrop {
    using ECDSA for bytes32;

    address public immutable TRUSTED_SIGNER;

    mapping(address => uint256) public nonces;

    event Funded(address indexed sender, uint256 amount);
    event Claimed(address indexed account, uint256 amount, uint256 nonce);

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

    /// @notice Claims ETH using a signature that can only be used once.
    function claim(uint256 amount, uint256 deadline, bytes calldata signature) external {
        require(amount > 0, "zero amount");
        require(block.timestamp <= deadline, "signature expired");
        require(address(this).balance >= amount, "insufficient airdrop balance");

        uint256 nonce = nonces[msg.sender];
        bytes32 digest = getClaimDigest(msg.sender, amount, nonce, deadline);
        address recovered = digest.recover(signature);
        require(recovered == TRUSTED_SIGNER, "invalid signature");

        nonces[msg.sender] = nonce + 1;

        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "ETH transfer failed");

        emit Claimed(msg.sender, amount, nonce);
    }

    /// @notice Returns the digest that `TRUSTED_SIGNER` must sign for this fixed version.
    /// @dev    Includes domain separation and nonce/deadline replay protection.
    function getClaimDigest(address account, uint256 amount, uint256 nonce, uint256 deadline)
        public
        view
        returns (bytes32)
    {
        bytes32 messageHash =
            keccak256(abi.encodePacked(address(this), block.chainid, account, amount, nonce, deadline));
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    }
}
