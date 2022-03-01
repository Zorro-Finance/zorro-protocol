// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../libraries/SafeERC20.sol";

import "../interfaces/IERC20.sol";

import "../helpers/Ownable.sol";

/// @title PoolPublic: The public pool contract. Hold all Zorro tokens deemed for public pool at inception and gradually emits to ZorroController contract based on market conditions
contract PoolPublic is Ownable {
  using SafeERC20 for IERC20;

  /* Constructor */

  /// @notice Constructor
  /// @param _zorroTokenAddress The Zorro token address
  /// @param _controller The address of the ZorroController 
  /// @param _timelockOwner The address of the TimelockController that should own this contract
  constructor(address _zorroTokenAddress, address _controller, address _timelockOwner) {
    // Set Zorro token address
    ZORRO = _zorroTokenAddress;
    // Set controller address
    controller = _controller;
    // Allow controller to spend tokens on this contract
    allowControllerToSpend();
    // Set owner of this contract to Timelock controller address
    transferOwnership(_timelockOwner);
  }

  /* State */

  address public ZORRO; // Zorro token contract address
  address public controller; // ZorroController contract address

  /* Events */
  event SetController(address indexed _controller);

  /* Functions */
  /// @notice Increases spending allowance to max amount for Zorro Controller
  function allowControllerToSpend() internal {
    IERC20(ZORRO).safeIncreaseAllowance(controller, type(uint256).max);
  }

  /// @notice setter for controller
  function setController(address _controller) external onlyOwner {
    // Update controller
    controller = _controller;
    // Reset spending allowance for new controller
    allowControllerToSpend();
    // Emit event
    emit SetController(_controller);
  }

}
