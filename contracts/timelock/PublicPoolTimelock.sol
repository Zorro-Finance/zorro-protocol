// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/governance/TimelockController.sol";

import "../interfaces/IVault.sol";

/// @title PublicPoolTimelock: A contract that owns the public pool, for safety
contract PublicPoolTimelock is TimelockController {
    /* Constructors */
    constructor(
        uint256 _minDelay,
        address[] memory _proposers,
        address[] memory _executors
    ) TimelockController(_minDelay, _proposers, _executors) {}

    /* No timelock functions */

}
