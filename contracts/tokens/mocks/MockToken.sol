// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IMockERC20Upgradeable is IERC20Upgradeable {
    function mint(address _account, uint256 _amount) external;
}

contract MockERC20Upgradeable is IMockERC20Upgradeable, ERC20Upgradeable {
    function mint(address _account, uint256 _amount) public {
        _mint(_account, _amount);
    }
}