// SPDX-License-Identifier: MIT

pragma solidity >0.5.16;

interface IUnitroller {
    function markets ( address ) external view returns ( bool isListed, uint256 collateralFactorMantissa, uint256 liquidationFactorMantissa, uint256 liquidationIncentiveMantissa, uint256 activeCollateralUSDCap, uint256 activeCollateralCTokenUsage);
}