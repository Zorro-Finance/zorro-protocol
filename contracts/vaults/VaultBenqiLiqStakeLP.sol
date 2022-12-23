// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/TraderJoe/IMasterChefJoeV3.sol";

import "./_VaultBaseLiqStakeLP.sol";

contract VaultBenqiAVAXLiqStakeLP is VaultBaseLiqStakeLP {
    function pendingLPFarmRewards() public view override returns (uint256 pendingRewards) {
        (pendingRewards,,,) = IMasterChefJoeV3(farmContractAddress).pendingTokens(pid, address(this));
    }
}
