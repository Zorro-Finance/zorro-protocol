// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

/// @title FinanceTimelock: A contract that owns all financial pools (public, treasury, founder, team), for safety
contract FinanceTimelock is TimelockControllerUpgradeable {
    /* No timelock functions */
}
