// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../VaultApeLending.sol";

import "../../interfaces/ApeLending/ICErc20Interface.sol";

import "../../interfaces/ApeLending/IRainMaker.sol";

import "../../interfaces/ApeLending/IUnitroller.sol";

contract MockVaultApeLending is VaultApeLending {
    // TODO: fill in necessary methods to be able to run tests
}

// TODO: Fill in these methods
contract MockApeLendingPool is ICErc20Interface {
    function mint(uint mintAmount) external returns (uint) {

    }

    function redeem(uint redeemTokens) external returns (uint) {

    }

    function redeemUnderlying(uint redeemAmount) external returns (uint) {

    }

    function borrow(uint borrowAmount) external returns (uint) {

    }

    function repayBorrow(uint repayAmount) external returns (uint) {

    }

    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint) {

    }

    function borrowBalanceCurrent(address account) external returns (uint) {

    }

    function balanceOfUnderlying(address owner) external returns (uint) {

    }

    function getCash() external view returns (uint) {

    }
}

contract MockApeLendingRainMaker is IRainMaker {
    function claimComp(address holder) external {

    }
}

contract MockApeLendingUnitroller is IUnitrollerApeLending {
    function markets ( address ) external view returns ( bool isListed, uint256 collateralFactorMantissa, uint256 liquidationFactorMantissa, uint256 liquidationIncentiveMantissa, uint256 activeCollateralUSDCap, uint256 activeCollateralCTokenUsage) {

    }
}
