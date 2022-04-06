// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/finance/VestingWallet.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title ModifiedVestingWallet: Vesting wallet designed to be used for founders, team members, and the treasury
contract ModifiedVestingWallet is VestingWallet, Ownable {

    /* Constructor */
    constructor(
        address _timelockOwner,
        address _beneficiaryAddress,
        uint64 _startTimestamp,
        uint64 _durationSeconds
    ) VestingWallet(_beneficiaryAddress, _startTimestamp, _durationSeconds) {
        transferOwnership(_timelockOwner);
    }
}
