// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/PancakeSwap/IMasterChef.sol";

import "./_VaultBaseLiqStakeLP.sol";

contract VaultStaderBNBLiqStakeLP is VaultBaseLiqStakeLP {
    function pendingLPFarmRewards() public view override returns (uint256 pendingRewards) {
        pendingRewards = IPCSMasterChef(farmContractAddress).pendingCake(pid, address(this));
    }
}