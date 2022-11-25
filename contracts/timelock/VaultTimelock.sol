// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

import "../interfaces/Zorro/Vaults/IVault.sol";

/// @title VaultTimelock: A contract that owns all deployed implementations of IVault for safety
contract VaultTimelock is TimelockControllerUpgradeable {
    /* No timelock functions */
    function earn(
        address _vaultAddress,
        uint256 _maxMarketMovement
    ) public onlyRole(EXECUTOR_ROLE) {
        IVault(_vaultAddress).earn(_maxMarketMovement);
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
