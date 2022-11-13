// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../VaultBenqiLending.sol";

import "../../interfaces/Benqi/IQiErc20.sol";

import "../../interfaces/Benqi/IQiTokenSaleDistributor.sol";

import "../../interfaces/Benqi/IUnitroller.sol";

contract MockVaultBenqiLending is VaultBenqiLending {
    // TODO: Fill in with necessary functions
}

// TODO: Fill in remaining here: 

contract MockBenqiLendingPool is IQiErc20 {
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

    function _addReserves(uint addAmount) external returns (uint) {

    }

    function transfer(address dst, uint amount) external returns (bool) {

    }

    function transferFrom(address src, address dst, uint amount) external returns (bool) {

    }

    function approve(address spender, uint amount) external returns (bool) {

    }

    function allowance(address owner, address spender) external view returns (uint) {

    }

    function balanceOf(address owner) external view returns (uint) {

    }

    function balanceOfUnderlying(address owner) external returns (uint) {

    }

    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint) {

    }

    function borrowRatePerTimestamp() external view returns (uint) {

    }

    function supplyRatePerTimestamp() external view returns (uint) {

    }

    function totalBorrowsCurrent() external returns (uint) {

    }

    function borrowBalanceCurrent(address account) external returns (uint) {

    }

    function getCash() external view returns (uint) {

    }

    function seize(address liquidator, address borrower, uint seizeTokens) external returns (uint) {

    }
}

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

