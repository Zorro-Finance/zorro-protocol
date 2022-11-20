// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../VaultApeLending.sol";

import "../../interfaces/Lending/ILendingToken.sol";

import "../../interfaces/ApeLending/IRainMaker.sol";

import "../../interfaces/ApeLending/IUnitroller.sol";

contract MockVaultApeLending is VaultApeLending {
    // TODO: fill in necessary methods to be able to run tests
}

contract MockApeLendingRainMaker is IRainMaker {
    function claimComp(address holder) external {

    }
}

contract MockApeLendingUnitroller is IUnitrollerApeLending {
    function markets ( address ) external view returns ( bool isListed, uint256 collateralFactorMantissa, uint256 liquidationFactorMantissa, uint256 liquidationIncentiveMantissa, uint256 activeCollateralUSDCap, uint256 activeCollateralCTokenUsage) {

    }
}
