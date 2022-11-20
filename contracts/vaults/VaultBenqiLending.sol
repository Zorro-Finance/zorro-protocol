// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_VaultLending.sol";

import "../interfaces/Benqi/IQiTokenSaleDistributor.sol";

/// @title Vault contract for Benqi leveraged lending strategies
contract VaultBenqiLending is VaultLending {
    /* Functions */

    /// @notice Claims unclaimed rewards from lending protocols
    function _claimLendingRewards() internal override {
        IQiTokenSaleDistributor(farmContractAddress).claim();
    }
}

contract VaultBenqiLendingAVAX is VaultBenqiLending {}
