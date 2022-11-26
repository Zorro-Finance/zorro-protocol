// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_VaultLending.sol";

import "../interfaces/Benqi/IQiTokenSaleDistributor.sol";

/// @title Vault contract for Benqi leveraged lending strategies
contract VaultBenqiLending is VaultLending {
    /* Functions */

    /// @notice Claims unclaimed rewards from lending protocols
    /// @param _amount Amount to unfarm (unused- only present to conform to abstract contract)
    function _unfarm(uint256 _amount) internal override {
        // Preflight check (unused - just here to satisfy compiler)
        require(_amount>=0);

        // Claim any outstanding rewards
        IQiTokenSaleDistributor(farmContractAddress).claim();

        // TODO: See VaultApeLending and mimic the changes made there
    }
}

contract VaultBenqiLendingAVAX is VaultBenqiLending {}
