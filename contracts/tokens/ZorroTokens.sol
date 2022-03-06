// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/utils/Address.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract ZorroControllerOwnable is Ownable {
    /* Modifiers */
    modifier onlyZorroController() {
        require(_msgSender() == zorroControllerAddress, "!zorroController");
        _;
    }

    /* State */
    address public zorroControllerAddress;
}

/// @title The Zorro token (cross chain)
contract Zorro is ERC20("ZORRO", "ZOR"), ZorroControllerOwnable {
    /* Constructor */
    constructor(address _zorroController) {
        zorroControllerAddress = _zorroController;
    }

    /* Functions */
    /// @notice Allows authorized minting of the Zorro token to a specified address
    /// @param _to The address to mint to
    /// @param _amount The amount to mint
    function mint(address _to, uint256 _amount) public onlyZorroController {
        // TODO: change modifier for this function
        _mint(_to, _amount);
    }

    /// @notice Allows authorized burning of the Zorro token from a specified account
    /// @param _account The address to transfer ZOR from for burning
    /// @param _amount The amount of ZOR to transfer and burn
    function burn(address _account, uint256 _amount) public onlyZorroController {
        // TODO change modifier here
        _burn(_account, _amount);
    }
}

/// @title Zorro USD synthetic token (used for bridges)
contract ZUSDC is ERC20("ZORRO_USDC", "ZUSDC"), ZorroControllerOwnable {
    /* Constructor */
    constructor(address _zorroController) {
        zorroControllerAddress = _zorroController;
    }

    /* Functions */
    /// @notice Mints ERC20 tokens
    /// @dev Can only be called by owner
    /// @param _to The address to send minted tokens to
    /// @param _amount The amount of tokens to mint
    function mint(address _to, uint256 _amount) public onlyZorroController {
        _mint(_to, _amount);
    }

    /// @notice Burns ERC20 tokens
    /// @dev Can only be called by owner
    /// @param _account The address to burn tokens from
    /// @param _amount The amount of tokens to burn
    function burn(address _account, uint256 _amount) public onlyZorroController {
        _burn(_account, _amount);
    }
}
