// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SimpleAMM} from "./SimpleAMM.sol";

/// @title VulnerableLending
/// @notice A toy lending market that trusts an AMM spot price as its oracle.
/// @dev The vulnerability is that `maxBorrow` changes immediately when the AMM reserves are manipulated.
contract VulnerableLending {
    uint256 public constant PRICE_SCALE = 1e18;
    uint256 public constant BPS = 10_000;
    uint256 public constant LTV_BPS = 5_000; // 50%

    SimpleAMM public immutable oracle;

    uint256 public debtAssetLiquidity;

    mapping(address => uint256) public collateralDeposits;
    mapping(address => uint256) public debtBorrowed;
    mapping(address => uint256) public debtAssetBalances;

    event Funded(uint256 amount);
    event Deposited(address indexed account, uint256 amount);
    event Borrowed(address indexed account, uint256 amount);

    constructor(SimpleAMM oracle_) {
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
        uint256 collateralValue = (collateralDeposits[account] * oracle.getSpotPrice()) / PRICE_SCALE;
        return (collateralValue * LTV_BPS) / BPS;
    }

    /// @notice Borrows virtual debt assets using the current AMM spot price.
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
