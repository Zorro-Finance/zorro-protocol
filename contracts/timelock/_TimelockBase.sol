// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

/// @title TimelockBase: Base contract for all Zorro Timelocks
contract TimelockBase is TimelockControllerUpgradeable {
    /* Constructor */

    /// @notice Initializer function for timelock
    /// @param _minDelay Min timelock period
    /// @param _proposers Proposer role addresses
    /// @param _executors Executor role addresses
    function initialize(
        uint256 _minDelay,
        address[] memory _proposers,
        address[] memory _executors
    ) public initializer {
        super.__TimelockController_init(
            _minDelay,
            _proposers,
            _executors
        );
    }
}
