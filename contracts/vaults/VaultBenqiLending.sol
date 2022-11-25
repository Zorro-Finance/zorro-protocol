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
        IQiTokenSaleDistributor(farmContractAddress).claim();
    }
}

contract VaultBenqiLendingAVAX is VaultBenqiLending {}
