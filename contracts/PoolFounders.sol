// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./helpers/ModifiedPaymentSplitter.sol";

/*
TODO
Modified payment splitter
- Ownable by TimelockController (ideally with a multisig)
- Can adjust shares per payee
- Accumulated (unreleased) tokens - OK for payee to pull this before down adjustment of shares, as it represents shares of future earnings
*/
contract PoolFounders is ModifiedPaymentSplitter {
  constructor(address[] memory payees, uint256[] memory shares_) ModifiedPaymentSplitter(payees, shares_) payable {}
}