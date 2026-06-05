// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SimpleAMM
/// @notice A deliberately simplified constant-product AMM used as a manipulable spot-price oracle.
/// @dev This contract tracks virtual reserves only. It is for security education, not production use.
contract SimpleAMM {
    uint256 public constant PRICE_SCALE = 1e18;

    uint256 public collateralReserve;
    uint256 public debtAssetReserve;

    event SwappedDebtForCollateral(uint256 debtIn, uint256 collateralOut);

    constructor(uint256 collateralReserve_, uint256 debtAssetReserve_) {
        require(collateralReserve_ > 0, "zero collateral reserve");
        require(debtAssetReserve_ > 0, "zero debt reserve");

        collateralReserve = collateralReserve_;
        debtAssetReserve = debtAssetReserve_;
    }

    /// @notice Returns the current spot price of 1 collateral token in debt-asset units.
    function getSpotPrice() external view returns (uint256) {
        return (debtAssetReserve * PRICE_SCALE) / collateralReserve;
    }

    /// @notice Buys collateral with the debt asset, increasing the collateral spot price.
    function swapDebtForCollateral(uint256 debtIn) external returns (uint256 collateralOut) {
        require(debtIn > 0, "zero debt in");

        uint256 invariant = collateralReserve * debtAssetReserve;
        uint256 newDebtReserve = debtAssetReserve + debtIn;
        uint256 newCollateralReserve = invariant / newDebtReserve;

        collateralOut = collateralReserve - newCollateralReserve;
        require(collateralOut > 0, "zero collateral out");

        collateralReserve = newCollateralReserve;
        debtAssetReserve = newDebtReserve;

        emit SwappedDebtForCollateral(debtIn, collateralOut);
    }
}
