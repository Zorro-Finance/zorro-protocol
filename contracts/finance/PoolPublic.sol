// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title PoolPublic: The public pool contract. Hold all Zorro tokens deemed for public pool at inception and gradually emits to ZorroController contract based on market conditions
contract PoolPublic is Initializable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* Constructor */

    /// @notice Constructor
    /// @param _zorroTokenAddress The Zorro token address
    /// @param _controller The address of the ZorroController
    function initialize(
        address _zorroTokenAddress,
        address _controller
    ) public initializer {
        // Set Zorro token address
        ZORRO = _zorroTokenAddress;
        // Set controller address
        controller = _controller;
        // Allow controller to spend tokens on this contract
        _allowControllerToSpend();
        // TODO: For some reason, owner is being set to the ZERO address
    }
    
    /* State */

    address public ZORRO; // Zorro token contract address
    address public controller; // ZorroController contract address

    /* Events */
    event SetController(address indexed _controller);

    /* Functions */
    /// @notice Increases spending allowance to max amount for Zorro Controller
    function _allowControllerToSpend() internal {
        IERC20Upgradeable(ZORRO).safeIncreaseAllowance(controller, type(uint256).max);
    }

    /// @notice setter for controller
    function setController(address _controller) external onlyOwner {
        // Update controller
        controller = _controller;
        // Reset spending allowance for new controller
        _allowControllerToSpend();
        // Emit event
        emit SetController(_controller);
    }
}
