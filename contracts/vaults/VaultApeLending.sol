// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_VaultLending.sol";

import "../interfaces/ApeLending/IRainMaker.sol";

/// @title Vault contract for ApeLending leveraged lending strategies
contract VaultApeLending is VaultLending {
    /* Functions */

    /// @notice Claims unclaimed rewards from lending protocols
    function _claimLendingRewards() internal override {
        IRainMaker(farmContractAddress).claimComp(address(this));
    }
}

contract VaultApeLendingETH is VaultApeLending {}
