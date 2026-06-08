// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TWAPOracle} from "./TWAPOracle.sol";

/// @title FixedLending
/// @notice Same toy lending market as `VulnerableLending`, but collateral value is priced
///         with a TWAP oracle instead of the manipulable AMM spot price.
/// @dev Fix: `maxBorrow` calls `TWAPOracle.consult()` so a single-block reserve spike
///      cannot instantly inflate borrowing power.
contract FixedLending {
    uint256 public constant PRICE_SCALE = 1e18;
    uint256 public constant BPS = 10_000;
    uint256 public constant LTV_BPS = 5_000; // 50%

    TWAPOracle public immutable oracle;

    uint256 public debtAssetLiquidity;

    mapping(address => uint256) public collateralDeposits;
    mapping(address => uint256) public debtBorrowed;
    mapping(address => uint256) public debtAssetBalances;

    event Funded(uint256 amount);
    event Deposited(address indexed account, uint256 amount);
    event Borrowed(address indexed account, uint256 amount);

    constructor(TWAPOracle oracle_) {
        oracle = oracle_;
    }

    /// @notice Funds the toy lending pool with virtual debt-asset liquidity.
    function fundDebtAsset(uint256 amount) external {
        require(amount > 0, "zero amount");

        debtAssetLiquidity += amount;

        emit Funded(amount);
    }

    /// @notice Deposits virtual collateral into the toy lending market.
    function depositCollateral(uint256 amount) external {
        require(amount > 0, "zero amount");

        collateralDeposits[msg.sender] += amount;

        emit Deposited(msg.sender, amount);
    }

    function maxBorrow(address account) public view returns (uint256) {
        uint256 collateralValue = (collateralDeposits[account] * oracle.consult()) / PRICE_SCALE;
        return (collateralValue * LTV_BPS) / BPS;
    }

    /// @notice Borrows virtual debt assets using the TWAP oracle price.
    function borrow(uint256 amount) external {
        require(amount > 0, "zero amount");
        require(debtAssetLiquidity >= amount, "insufficient liquidity");
        require(debtBorrowed[msg.sender] + amount <= maxBorrow(msg.sender), "insufficient collateral");

        debtBorrowed[msg.sender] += amount;
        debtAssetBalances[msg.sender] += amount;
        debtAssetLiquidity -= amount;

        emit Borrowed(msg.sender, amount);
    }
}
