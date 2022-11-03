// SPDX-License-Identifier: MIT

pragma solidity >0.5.17;

interface IUnitroller {
    function markets ( address ) external view returns ( bool isListed, uint256 collateralFactorMantissa, bool isQied);
    function claimReward(uint8 rewardType, address payable holder) external;
}