// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./helpers/ERC20.sol";

import "./libraries/Address.sol";

import "./libraries/SafeERC20.sol";

import "./helpers/Ownable.sol";

/// @title The Zorro token (cross chain)
contract Zorro is ERC20("ZORRO", "ZOR"), Ownable {
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}

/// @title Zorro USD synthetic token (used for bridges)
contract ZUSDC is ERC20("ZORRO_USDC", "ZUSDC"), Ownable {
    /// @notice Mints ERC20 tokens
    /// @dev Can only be called by owner
    /// @param _to The address to send minted tokens to
    /// @param _amount The amount of tokens to mint
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    /// @notice Burns ERC20 tokens
    /// @dev Can only be called by owner
    /// @param _account The address to burn tokens from
    /// @param _amount The amount of tokens to burn
    function burn(address _account, uint256 _amount) public onlyOwner {
        _burn(_account, _amount);
    }
}
