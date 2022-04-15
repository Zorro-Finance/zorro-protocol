// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/utils/Address.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IZorro.sol";


/// @title The Zorro token (cross chain)
contract Zorro is IZorro, ERC20("ZORRO", "ZOR"), Ownable {
    /* Modifiers */
    modifier onlyZorroController() {
        require(_msgSender() == zorroControllerAddress, "!zorroController");
        _;
    }

    /* State */
    address public zorroControllerAddress;

    /* Setters */
    function setZorroController(address _zorroController) external onlyOwner {
        zorroControllerAddress = _zorroController;
    }
    
    /* Functions */
    /// @notice Allows authorized minting of the Zorro token to a specified address
    /// @param _to The address to mint to
    /// @param _amount The amount to mint
    function mint(address _to, uint256 _amount) public onlyZorroController {
        _mint(_to, _amount);
    }

    /// @notice Allows authorized burning of the Zorro token from a specified account
    /// @param _account The address to transfer ZOR from for burning
    /// @param _amount The amount of ZOR to transfer and burn
    function burn(address _account, uint256 _amount)
        public
        onlyZorroController
    {
        _burn(_account, _amount);
    }
}
