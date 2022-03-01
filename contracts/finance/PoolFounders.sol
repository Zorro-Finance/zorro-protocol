// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../helpers/ModifiedPaymentSplitter.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


/// @title PoolFounders: Contract for managing finances/token allocation for the Founders pool. Ownable and intended to be controlled by a TimelockController
contract PoolFounders is ModifiedPaymentSplitter, Ownable {
  using SafeMath for uint256;

  /* State */
  address public ZORRO; // Zorro token address

  /* Events */
  event UpdatedShares(address indexed _payee, uint256 indexed _oldShares, uint256 indexed _newShares);

  /* Constructor */

  /// @notice Constructor (inherits from parent constructor, sets ownership)
  constructor(address _timelockOwner, address _zorroToken, address[] memory _payees, uint256[] memory _shares) ModifiedPaymentSplitter(_payees, _shares) payable {
    // Set ownership to provided TimelockController owner
    transferOwnership(_timelockOwner);
    // Set Zorro token address
    ZORRO = _zorroToken;
  }

  /// @notice change the value of shares for a particular payee (for ERC20)
  function updateSharesERC20(address payable _payee, uint256 _newShares) public onlyOwner {
    // Release any outstanding funds owed to each payee first
    uint256 numPayees = numPayees();
    for (uint256 i = 0; i < numPayees; i++) {
      release(IERC20(ZORRO), payees[i]);
    }
    // Get current number of shares
    uint256 oldShares = shares(_payee);
    // Update the new number of shares for that payee
    _shares[_payee] = _newShares;
    // Update the total number of shares 
    _totalShares = _totalShares.sub(oldShares).add(_newShares);
    // Emit event to show update
    emit UpdatedShares(_payee, oldShares, _newShares);
  }
}