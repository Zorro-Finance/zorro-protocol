// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/governance/TimelockController.sol";

import "../interfaces/IVault.sol";

/// @title VaultTimelock: A contract that owns all deployed implementations of IVault for safety
contract VaultTimelock is TimelockController {
    /* Constructors */
    constructor(
        uint256 _minDelay,
        address[] memory _proposers,
        address[] memory _executors
    ) TimelockController(_minDelay, _proposers, _executors) {}

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
