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
}