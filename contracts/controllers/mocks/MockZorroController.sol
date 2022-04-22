// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ZorroController.sol";

contract MockZorroController is ZorroController {
    function addTranche(
        uint256 _pid,
        address _account,
        TrancheInfo memory _trancheInfo
    ) public {
        trancheInfo[_pid][_account].push(_trancheInfo);
        poolInfo[_pid].totalTrancheContributions = poolInfo[_pid].totalTrancheContributions + _trancheInfo.contribution;
    }

    function setLastRewardBlock(
        uint256 _pid,
        uint256 _block
    ) public {
        poolInfo[_pid].lastRewardBlock = _block;
    }

    event UpdatedPool(uint256 _amount);

    function updatePoolMod(uint256 _pid) public {
        uint256 _res = updatePool(_pid);

        emit UpdatedPool(_res);
    }

    function _fetchFundsFromPublicPool(uint256 _amount) internal override {
        // Do nothing. Dummy func.
    }
}