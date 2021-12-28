// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./helpers/ERC20.sol";

import "./libraries/Address.sol";

import "./libraries/SafeERC20.sol";

import "./helpers/Ownable.sol";

contract Zorro is ERC20("ZORRO", "ZOR"), Ownable {
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}
