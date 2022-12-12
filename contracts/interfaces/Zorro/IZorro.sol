// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// @title IZorro
interface IZorro {
    function setZorroController(address _zorroController) external;

    function mint(address _to, uint256 _amount) external;
}
