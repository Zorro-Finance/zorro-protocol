// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../VaultAcryptosSingle.sol";

import "../../tokens/mocks/MockToken.sol";

contract MockVaultFactoryAcryptosSingle is VaultFactoryAcryptosSingle {
    
}

contract MockVaultAcryptosSingle is VaultAcryptosSingle {
    function swapEarnedToUSDC(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) public {
        _swapEarnedToUSDC(_earnedAmount, _destination, _maxMarketMovementAllowed, _rates);
    }

    function revShareOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) public {
        _revShareOnChain(_amount, _maxMarketMovementAllowed, _rates);
    }

    function buybackOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) public {
        _buybackOnChain(_amount, _maxMarketMovementAllowed, _rates);
    }
}

contract MockAcryptosVault is IAcryptosVault, MockERC20Upgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event AddedLiquidity(uint256 _amount, uint256 _liquidity);
    event RemovedLiquidity(uint256 _amount);

    address public token0;
    address public burnAddress;

    function setToken0Address(address _token) public {
        token0 = _token;
    }

    function setBurnAddress(address _burn) public {
        burnAddress = _burn;
    }

    function deposit(uint256 _amount) public {
        IERC20Upgradeable(token0).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _liquidity = 1 ether; // Hard code for tests
        _mint(msg.sender, _liquidity);
        emit AddedLiquidity(_amount, _liquidity);
    }

    function withdraw(uint256 _shares) public {
        IERC20Upgradeable(address(this)).safeTransferFrom(msg.sender, burnAddress, _shares);
        emit RemovedLiquidity(2 ether); // Hard code for tests
    }
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
contract MockACS is MockERC20Upgradeable {}