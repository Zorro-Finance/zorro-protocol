// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_VaultLending.sol";

import "../interfaces/ApeLending/IRainMaker.sol";

/// @title Vault contract for ApeLending leveraged lending strategies
contract VaultApeLending is VaultLending {
    /* Functions */

    /// @notice Claims unclaimed rewards from lending protocols
    /// @param _amount Amount to unfarm
    function _unfarm(uint256 _amount) internal override {
        // Claim any outstanding rewards
        IRainMaker(farmContractAddress).claimComp(address(this));

        // TODO: Based on the new logic, we should probably be convering the earn to want. 

        // Withdraw appropriate amount
        _withdrawSome(_amount);

        // TODO: Need to re-supply/rebalance after (farm())? Check Acryptos
    }
}

contract VaultApeLendingETH is VaultApeLending {}
