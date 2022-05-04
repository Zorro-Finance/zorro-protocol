// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../VaultAcryptosSingle.sol";

import "../../tokens/mocks/MockToken.sol";

contract MockVaultFactoryAcryptosSingle is VaultFactoryAcryptosSingle {
    
}

contract MockVaultAcryptosSingle is VaultAcryptosSingle {

}

contract MockAcryptosFarm is IAcryptosFarm, MockERC20Upgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event Deposited(address indexed _want, uint256 indexed _amount);
    event Withdrew(address indexed _want, uint256 indexed _amount);

    address public burnAddress;
    address public wantToken;

    function setWantAddress(address _wantToken) public {
        wantToken = _wantToken;
    }

    function setBurnAddress(address _burnAddress) public {
        burnAddress = _burnAddress;
    }

    function deposit(address _lpToken, uint256 _amount) public {
        IERC20Upgradeable(wantToken).safeTransferFrom(msg.sender, burnAddress, _amount);
        emit Deposited(_lpToken, _amount);
    }

    function withdraw(address _lpToken, uint256 _amount) public {
        IMockERC20Upgradeable(wantToken).mint(msg.sender, _amount);
        emit Withdrew(_lpToken, _amount);
    }
}

contract MockBUSD is MockERC20Upgradeable {}