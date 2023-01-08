// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/finance/VestingWallet.sol";

/// @title TreasuryVestingWallet: The vesting wallet for ZOR tokens, redeemable by PoolTeam
contract TeamVestingWallet is VestingWallet, Ownable {
    /* Constructor */
    constructor(
        address beneficiaryAddress,
        uint64 startTimestamp,
        uint64 durationSeconds,
        uint64 _cliffSeconds
    ) payable VestingWallet(beneficiaryAddress, startTimestamp, durationSeconds) {
        require(cliffSeconds < durationSeconds, "cliff too large");
        cliffSeconds = _cliffSeconds;
    }

    /* State */
    uint256 public cliffSeconds; // Cliff duration in seconds from start()

    /* Functions */

    /// @notice Modified version of VestingWallet.release() (checks to see if cliff is met first)
    /// @param token The token to release
    function release(address token) public override {
        // Check cliff period
        require(block.timestamp - start() >= cliffSeconds, "cliff not yet reached");

        // Run release() as normal
        super.release(token);
    }
}