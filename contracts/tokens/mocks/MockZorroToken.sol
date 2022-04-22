// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/IZorro.sol";

contract MockZorroToken is IZorro {
    event Minted(address indexed _to, uint256 indexed _amount);
    event Burned(address indexed _account, uint256 indexed _amount);

    function setZorroController(address _zorroController) external {

    }

    function mint(address _to, uint256 _amount) external {
        emit Minted(_to, _amount);
    }

    function burn(address _account, uint256 _amount) external {
        emit Burned(_account, _amount);
    }
}