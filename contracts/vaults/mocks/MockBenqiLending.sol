// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../VaultBenqiLending.sol";

import "../../interfaces/Benqi/IQiTokenSaleDistributor.sol";

import "../../interfaces/Benqi/IUnitroller.sol";

contract MockVaultBenqiLending is VaultBenqiLending {
    // TODO: Fill in with necessary functions
}

// TODO: Fill in remaining here: 

contract MockBenqiTokenSaleDistributor is IQiTokenSaleDistributor {
    function claim() external {

    }
}

contract MockBenqiUnitroller is IUnitrollerBenqi {
    function markets ( address ) external view returns ( bool isListed, uint256 collateralFactorMantissa, bool isQied) {

    }

    function claimReward(uint8 rewardType, address payable holder) external {

    }
}

