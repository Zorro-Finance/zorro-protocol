// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PoolTreasury is Ownable {
  using SafeERC20 for IERC20;

  /// @notice Constructor
  /// @param _timelockOwner The address of the Timelock contract that should own this contract
  constructor(address _timelockOwner) {
    // Transfer ownership immediately to the Timelock owner
    transferOwnership(_timelockOwner);
  }

  /// @notice transfer accumulated ERC20 token on this contract to specified recipient. Used for distribution of warchest funds.
  /// @param _token address of token to transfer out
  /// @param _amount amount of token to transfer, up to maximum. Specifying uint256(-1) will transfer maximum amount
  /// @param _recipient address of recipient to transfer to
  function transferTokenOut(address _token, uint256 _amount, address _recipient) external onlyOwner {
    // Check current balance
    uint256 bal = IERC20(_token).balanceOf(address(this));
    // Safety: If amount greater than balance, cap at balance
    if (_amount > bal) {
      _amount = bal;
    }
    // Transfer to recipient
    IERC20(_token).safeTransfer(_recipient, _amount);
  }

  /// @notice transfer accumulated ETH on this contract to specified recipient. Used for distribution of warchest funds.
  /// @param _amount amount of ETH to transfer, up to the balance on this contract. Specifying uint256(-1) will transfer maximum amount
  /// @param _recipient address of recipient to transfer to
  function transferETHOut(uint256 _amount, address payable _recipient) external onlyOwner {
    // Check current balance
    uint256 bal = address(this).balance;
    // Safety: If amount greater than balance, cap at balance
    if (_amount > bal) {
      _amount = bal;
    }
    // Transfer to recipient
    (bool sent, ) = _recipient.call{value: _amount}("");
    require(sent, "Failed to send Ether");
  }
}
