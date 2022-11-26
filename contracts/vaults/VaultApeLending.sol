// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_VaultLending.sol";

import "../interfaces/ApeLending/IRainMaker.sol";

/// @title Vault contract for ApeLending leveraged lending strategies
contract VaultApeLending is VaultLending {
    /* Functions */

    /// @notice Claims unclaimed rewards from lending protocols
    /// @param _amount Amount to unfarm (unused- only present to conform to abstract contract)
    function _unfarm(uint256 _amount) internal override {
        // Preflight check (unused - just here to satisfy compiler)
        require(_amount>=0);

        // Claim any outstanding rewards
        IRainMaker(farmContractAddress).claimComp(address(this));
    }
}

contract VaultApeLendingETH is VaultApeLending {}
