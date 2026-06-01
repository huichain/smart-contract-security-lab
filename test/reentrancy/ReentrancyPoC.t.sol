// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {VulnerableVault} from "../../src/reentrancy/VulnerableVault.sol";
import {ReentrancyAttacker} from "../../src/reentrancy/ReentrancyAttacker.sol";
import {FixedVault} from "../../src/reentrancy/FixedVault.sol";

/// @title ReentrancyPoC
/// @notice Proves that `VulnerableVault` can be drained by a classic
///         reentrancy attack. The vulnerable vault sends ETH to the user
///         BEFORE zeroing out the recorded balance, so an attacker contract
///         can re-enter `withdraw` from its `receive()` function.
contract ReentrancyPoC is Test {
    VulnerableVault internal vault;
    ReentrancyAttacker internal attacker;

    address internal victim = makeAddr("victim");
    address internal attackerEoa = makeAddr("attackerEoa");

    uint256 internal constant VICTIM_DEPOSIT = 10 ether;
    uint256 internal constant ATTACK_UNIT = 1 ether;

    function setUp() public {
        vault = new VulnerableVault();
        attacker = new ReentrancyAttacker(address(vault), ATTACK_UNIT);

        // Fund the EOAs that will interact with the vault.
        vm.deal(victim, VICTIM_DEPOSIT);
        vm.deal(attackerEoa, ATTACK_UNIT);
    }

    /// @notice Full PoC: attacker drains a 10 ETH vault with only 1 ETH of
    ///         their own capital by exploiting the reentrancy bug.
    function testExploit_DrainsVault() public {
        // 1. Honest user deposits into the vault.
        vm.prank(victim);
        vault.deposit{value: VICTIM_DEPOSIT}();
        assertEq(address(vault).balance, VICTIM_DEPOSIT, "vault should hold victim deposit");

        // 2. Attacker fires the exploit using only `ATTACK_UNIT` of their own ETH.
        vm.prank(attackerEoa);
        attacker.attack{value: ATTACK_UNIT}();

        // 3. The vault should be fully drained.
        assertEq(address(vault).balance, 0, "vault should be fully drained");

        // 4. The attacker contract should hold the victim's funds plus its own deposit.
        assertEq(
            address(attacker).balance,
            VICTIM_DEPOSIT + ATTACK_UNIT,
            "attacker should hold all stolen ETH"
        );
    }

    /// @notice Same attacker, same flow, but now targets `FixedVault`.
    ///         The exploit must revert and the victim's funds must remain safe.
    function testFix_BlocksReentrancy() public {
        FixedVault fixedVault = new FixedVault();
        ReentrancyAttacker fixedAttacker = new ReentrancyAttacker(address(fixedVault), ATTACK_UNIT);

        // Honest deposit into the fixed vault.
        vm.prank(victim);
        fixedVault.deposit{value: VICTIM_DEPOSIT}();
        assertEq(address(fixedVault).balance, VICTIM_DEPOSIT);

        // Attacker fires the same exploit; the whole transaction must revert.
        vm.prank(attackerEoa);
        vm.expectRevert();
        fixedAttacker.attack{value: ATTACK_UNIT}();

        // All state should roll back: victim funds intact, attacker stole nothing.
        assertEq(address(fixedVault).balance, VICTIM_DEPOSIT, "vault must preserve victim funds");
        assertEq(address(fixedAttacker).balance, 0, "attacker must not have stolen any ETH");
    }

    /// @notice Sanity check: the fix must not break legitimate user flows.
    function testFix_AllowsHonestWithdraw() public {
        FixedVault fixedVault = new FixedVault();

        vm.prank(victim);
        fixedVault.deposit{value: VICTIM_DEPOSIT}();

        uint256 victimBalanceBefore = victim.balance;

        vm.prank(victim);
        fixedVault.withdraw(VICTIM_DEPOSIT);

        assertEq(address(fixedVault).balance, 0, "vault should be fully withdrawn");
        assertEq(
            victim.balance,
            victimBalanceBefore + VICTIM_DEPOSIT,
            "victim should receive their funds"
        );
        assertEq(fixedVault.balances(victim), 0, "internal balance should be cleared");
    }
}
