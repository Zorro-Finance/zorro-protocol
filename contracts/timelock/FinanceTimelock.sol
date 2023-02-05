// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_TimelockBase.sol";

/// @title FinanceTimelock: A contract that owns all financial pools (public, treasury, founder, team), for safety
contract FinanceTimelock is TimelockBase {
    /* No timelock functions */
}
