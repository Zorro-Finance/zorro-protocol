// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../VaultAnkrPCSLiqStake.sol";

import "../../interfaces/Ankr/IBinancePool_R1.sol";

contract MockVaultAnkrLiqStakeLP is VaultAnkrLiqStakeLP {
    // TODO: Fill out any necessary methods for testing here
}

// TODO: Fill out below
contract MockAnkrLiqStakePoolBNB is IBinancePool_R1 {
    function stake() external payable {

    }

    function unstake(uint256 amount) external {

    }

    function distributeManual(uint256 wrId) external {

    }

    function distributeRewards(uint256 maxClaimers) external payable {

    }

    function pendingUnstakesOf(address account) external returns (uint256) {

    }

    function getMinimumStake() external view returns (uint256) {

    }

    function getRelayerFee() external view returns (uint256) {

    }

    function stakeAndClaimBonds() external payable {

    }

    function stakeAndClaimCerts() external payable {

    }

    function unstakeBonds(uint256 amount) external {

    }

    function unstakeCerts(uint256 shares) external {

    }
}