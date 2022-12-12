// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IZorroController.sol";

interface IZorroControllerActions {
    /* Functions */
    
    function getAdjustedRewards(
        IZorroControllerBase.TrancheInfo memory _tranche,
        uint256 _pendingRewards
    ) external view returns (uint256 rewardsDue, uint256 slashedRewards);

    function getTimeMultiplier(
        uint256 _durationInWeeks,
        bool _isTimeMultiplierActive
    ) external pure returns (uint256 timeMultiplier);

    function getUserContribution(
        uint256 _liquidityCommitted,
        uint256 _timeMultiplier
    ) external pure returns (uint256);
}
