// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_TimelockBase.sol";

import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

import "../interfaces/Zorro/Vaults/IVault.sol";

/// @title VaultTimelock: A contract that owns all deployed implementations of IVault for safety
contract VaultTimelock is TimelockBase {
    /* No timelock functions */
    
    function earn(
        address _vaultAddress
    ) public onlyRole(EXECUTOR_ROLE) {
        IVault(_vaultAddress).earn();
    }

    function farm(address _vaultAddress) public onlyRole(EXECUTOR_ROLE) {
        IVault(_vaultAddress).farm();
    }

    function pause(address _vaultAddress) public onlyRole(EXECUTOR_ROLE) {
        IVault(_vaultAddress).pause();
    }

    function unpause(address _vaultAddress) public onlyRole(EXECUTOR_ROLE) {
        IVault(_vaultAddress).unpause();
    }
}
