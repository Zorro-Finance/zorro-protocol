// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./helpers/ModifiedPaymentSplitter.sol";

import "./helpers/ModifiedVestingWallet.sol";

import "./helpers/Ownable.sol";

/*
TODO
Modified payment splitter
- Ownable by TimelockController (ideally with a multisig)
- Can add and remove payees
- Initializes by sending all shares to a "reserve" contract (100% ownership). This ownership by the reserve is reduced as more payees are added
- Adding a payee first loops through all current payees and triggers the release() function, then creates a new payee and assigns the desired amount of shares by taking them from the reserve
- Removing payee triggers the release() function to send funds to the beneficiary's VestingWallet, then a call to beneficiary's VestingWallet's stopVesting() function which releases vested funds and pays unvested funds back to this contract, replenishing the pool. The stopVesting() function calls returnUnvestedTokens() to replenish. 
*/
contract PoolTeam is ModifiedPaymentSplitter, Ownable {
  /**
     * @dev Creates an instance of `PaymentSplitter` where each account in `payees` is assigned the number of shares at
     * the matching position in the `shares` array.
     *
     * All addresses in `payees` must be non-zero. Both arrays must have the same non-zero length, and there must be no
     * duplicates in `payees`.
     */
    constructor(address[] memory payees, uint256[] memory shares_) ModifiedPaymentSplitter(payees, shares_) payable {
        
    }
}

/*
TODO
Modified Vesting Wallet
- Ownable by Modified PaymentSplitter above
- Has a stopVesting() function that accomplishes the following: 1) Releases vested funds for specified account 2) No longer permits releases on this account on this contract, 3) Sends vested funds back to the controller PaymentSplitter contract, by calling returnUnvestedTokens().
*/
contract TeamMemberVestingWallet is ModifiedVestingWallet {
  /**
     * @dev Set the beneficiary, start timestamp and vesting duration of the vesting wallet.
     */
    constructor(
        address beneficiaryAddress,
        uint64 startTimestamp,
        uint64 durationSeconds
    ) ModifiedVestingWallet(beneficiaryAddress, startTimestamp, durationSeconds) {}
}