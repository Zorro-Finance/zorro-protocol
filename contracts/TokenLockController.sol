// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./libraries/SafeERC20.sol";

import "./interfaces/IERC20.sol";

import "./helpers/Ownable.sol";

import "./helpers/Pausable.sol";

import "./helpers/ReentrancyGuard.sol";

import "./libraries/SafeMath.sol";

// TODO: Need modifer that only allows certain contracts to call

/// @title TokenLockController. Contract for securely locking, unlocking, and burning tokens
contract TokenLockController is Ownable, Pausable, ReentrancyGuard {
  /* 
  Libraries
  */
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  /*
  Constructor
  */
  constructor(address _owner) {
    // TODO - complete this
    // Immediately transfer ownership to specified owner
    transferOwnership(_owner);
  }

  /*
  Modifiers
  */
  /// @notice Requires caller to be in allowed list
  modifier onlyAllowedOperators() {
    require(allowedOperators[msg.sender] > 0, "Invalid caller");
    _;
  }

  /*
  State
  */
  address public lockableToken; // The ERC20 token's address that can be burned
  mapping(address => uint8) public allowedOperators; // Allowed callers of this contract. Mapping: contract address => 1 or 0. 1 means allowed.
  mapping(address => uint256) public lockedFunds; // Ledger of locked amount by account. Mapping: wallet address => amount locked
  address public burnAddress;

  /*
  Setters/Config
  */
  /// @notice Add an allowed operator to the allowedOperators mapping
  /// @param _newOperator The address of the new operator to add
  function addAllowedOperator(address _newOperator) public onlyOwner {
    allowedOperators[_newOperator] = 1;
  }

  /// @notice Remove an allowed operator from the allowedOperators mapping
  /// @param _operator The address of the new operator to remove
  function removeAllowedOperator(address _operator) public onlyOwner {
    allowedOperators[_operator] = 0;
  } 

  /*
  Financial functions
  */
  /// @notice Lock funds to this contract's ledger
  /// @dev Assumes that approval has already been given to this contract to transfer the ERC20 token
  /// @param _account The address whose funds should be locked. 
  /// @param _amount The amount of the token to lock
  function lockFunds(address _account, uint256 _amount) public onlyAllowedOperators {
    //  Transfer funds to this contract
    IERC20(lockableToken).safeTransferFrom(_account, address(this), _amount);
    // Lock funds on ledger
    lockedFunds[_account] = _amount;
  }

  /// @notice Unlock funds from this contract's ledger for a given user account
  /// @param _account The address whose funds should be unlocked. 
  /// @param _amount The amount of the token to lock
  /// @return The amount unlocked
  function unlockFunds(address _account, uint256 _amount) public onlyAllowedOperators returns (uint256) {
    // Determine currently locked funds
    uint256 _currentlyLocked = lockedFunds[_account];
    uint256 _amountToUnlock = _amount;
    // Ensure that only funds up to the max currently locked can be unlocked
    if (_amount > _currentlyLocked) {
      _amountToUnlock = _currentlyLocked;
    }
    // Unlock funds from ledger
    lockedFunds[_account] = _currentlyLocked.sub(_amountToUnlock);
    // Transfer funds back to account
    IERC20(lockableToken).transfer(_account, _amountToUnlock);
    // Return amount unlocked
    return _amountToUnlock;
  }

  /// @notice Burn funds that are held on this contract
  /// @param _amount The amount of the token to burn
  /// @return The amount burned
  function burnFunds(uint256 _amount) public onlyAllowedOperators returns (uint256) {
    // Get current balance on this contract
    uint256 _currentBal = IERC20(lockableToken).balanceOf(address(this));
    // Amount to burn must be less than total held by this contract
    require(_amount <= _currentBal, "Cannot burn more than avail");
    // Send funds to burn address
    IERC20(lockableToken).safeTransfer(burnAddress, _amount);
    // Return amount burned
    return _amount;
  }
}
