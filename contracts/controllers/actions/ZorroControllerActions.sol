// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SignedSafeMathUpgradeable.sol";

import "../../libraries/Math.sol";

import "../../interfaces/IZorroController.sol";

// TODO: Create interface for this contract

contract ZorroControllerActions is OwnableUpgradeable {
    /* Libraries */
    using SafeMathUpgradeable for uint256;
    using SignedSafeMathUpgradeable for int256;
    using CustomMath for uint256;

    /* Investments */

    /// @notice Splits rewards into rewards due and slashed rewards (if early withdrawal)
    /// @param _tranche TrancheInfo object
    /// @param _pendingRewards Qty of ZOR tokens as pending rewards
    /// @return rewardsDue The amount of ZOR rewards payable
    /// @return slashedRewards The amount of ZOR rewards slashed due to early withdrawals
    function getAdjustedRewards(
        IZorroControllerBase.TrancheInfo memory _tranche,
        uint256 _pendingRewards
    ) public view returns (uint256 rewardsDue, uint256 slashedRewards) {
        // Only process rewards > 0
        if (_pendingRewards <= 0) {
            return (0, 0);
        }
        // Check if this is an early withdrawal
        // If so, slash the accumulated rewards proportionally to the % time remaining before maturity of the time commitment
        // If not, distribute rewards as normal
        int256 _timeRemainingInCommitment = int256(_tranche.enteredVaultAt)
            .add(int256(_tranche.durationCommittedInWeeks.mul(1 weeks)))
            .sub(int256(block.timestamp));
        if (_timeRemainingInCommitment > 0) {
            slashedRewards = _pendingRewards
                .mul(uint256(_timeRemainingInCommitment))
                .div(_tranche.durationCommittedInWeeks.mul(1 weeks));
            rewardsDue = _pendingRewards.sub(slashedRewards);
        } else {
            rewardsDue = _pendingRewards;
        }
    }

    /// @notice Calculate time multiplier based on duration committed
    /// @dev For Zorro staking vault, returns 1e12 no matter what
    /// @param _durationInWeeks number of weeks committed into Vault
    /// @param _isTimeMultiplierActive Whether or not the time multiplier is active
    /// @return timeMultiplier Time multiplier factor, times 1e12
    function getTimeMultiplier(
        uint256 _durationInWeeks,
        bool _isTimeMultiplierActive
    )
        public
        pure
        returns (uint256 timeMultiplier)
    {
        timeMultiplier = 1e12;

        if (_isTimeMultiplierActive) {
            // Use sqrt(x * 10000)/100 to get better float point accuracy (see tests)
            timeMultiplier = ((_durationInWeeks.mul(1e4)).sqrt())
                .mul(1e12)
                .mul(2)
                .div(1000)
                .add(1e12);
        }
    }

    /// @notice The contribution of the user, meant to be used in rewards allocations
    /// @param _liquidityCommitted How many tokens staked (e.g. LP tokens)
    /// @param _timeMultiplier Time multiplier value (from getTimeMultiplier())
    /// @return uint256 The relative contribution of the user (unitless)
    function getUserContribution(
        uint256 _liquidityCommitted,
        uint256 _timeMultiplier
    ) public pure returns (uint256) {
        return _liquidityCommitted.mul(_timeMultiplier).div(1e12);
    }


}