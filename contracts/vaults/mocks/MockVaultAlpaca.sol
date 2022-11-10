// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../VaultAlpaca.sol";

import "../../tokens/mocks/MockToken.sol";

import "../libraries/VaultLibrary.sol";

import "../../interfaces/Alpaca/IAlpacaFairLaunch.sol";

import "../../interfaces/Alpaca/IAlpacaVault.sol";

contract MockVaultAlpaca is VaultAlpaca {
    function unfarm(uint256 _wantAmt) public {
        _unfarm(_wantAmt);
    }

    function swapEarnedToUSD(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed,
        VaultLibrary.ExchangeRates memory _rates
    ) public {
        _swapEarnedToUSD(
            _earnedAmount,
            _destination,
            _maxMarketMovementAllowed,
            _rates
        );
    }

    function revShareOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        VaultLibrary.ExchangeRates memory _rates
    ) public {
        _revShareOnChain(_amount, _maxMarketMovementAllowed, _rates);
    }

    function buybackOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        VaultLibrary.ExchangeRates memory _rates
    ) public {
        _buybackOnChain(_amount, _maxMarketMovementAllowed, _rates);
    }
}

contract MockAlpacaVault is IAlpacaVault, MockERC20Upgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event AddedLiquidity(uint256 _amount, uint256 _liquidity);
    event RemovedLiquidity(uint256 _amount);

    address public token0;
    address public burnAddress;
    uint256 private _dummy;

    function setToken0Address(address _token) public {
        token0 = _token;
    }

    function setBurnAddress(address _burn) public {
        burnAddress = _burn;
    }

    function totalToken() external view returns (uint256) {
        require(_dummy>=0);
        return 0;
    }

    function deposit(uint256 _amount) public payable {
        IERC20Upgradeable(token0).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        uint256 _liquidity = 1 ether; // Hard code for tests
        _mint(msg.sender, _liquidity);
        emit AddedLiquidity(_amount, _liquidity);
    }

    function withdraw(uint256 _shares) public {
        IERC20Upgradeable(address(this)).safeTransferFrom(
            msg.sender,
            burnAddress,
            _shares
        );
        uint256 _withdrawalAmt = 2 ether; // Hard code for tests
        IMockERC20Upgradeable(token0).mint(msg.sender, _withdrawalAmt);
        emit RemovedLiquidity(_withdrawalAmt);
    }

    function requestFunds(address targetedToken, uint256 amount) external {}

    function token() external view returns (address) {
        require(_dummy>=0);
        return address(0);
    }
}

contract MockAlpacaFarm is IFairLaunch, MockERC20Upgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event Deposited(address indexed _want, uint256 indexed _amount);
    event Withdrew(address indexed _want, uint256 indexed _amount);

    address public burnAddress;
    address public wantToken;
    uint256 private _dummy;

    function setWantAddress(address _wantToken) public {
        wantToken = _wantToken;
    }

    function setBurnAddress(address _burnAddress) public {
        burnAddress = _burnAddress;
    }

    function poolLength() external view returns (uint256) {
        require(_dummy>=0);
        return 0;
    }

    function addPool(
        uint256 _allocPoint,
        address _stakeToken,
        bool _withUpdate
    ) external {}

    function setPool(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external {}

    function pendingAlpaca(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        require(_dummy>=0);
        require(_pid>=0);
        require(_user != address(0));
        return 0;
    }

    function updatePool(uint256 _pid) external {}

    function deposit(
        address _for,
        uint256 _pid,
        uint256 _amount
    ) public {
        require(_for != address(0));
        require(_pid>=0);
        IERC20Upgradeable(wantToken).safeTransferFrom(
            msg.sender,
            burnAddress,
            _amount
        );
        emit Deposited(wantToken, _amount);
    }

    function withdraw(
        address _for,
        uint256 _pid,
        uint256 _amount
    ) public {
        require(_pid>=0);
        IMockERC20Upgradeable(wantToken).mint(_for, _amount);
        emit Withdrew(wantToken, _amount);
    }

    function withdrawAll(address _for, uint256 _pid) external {}

  function harvest(uint256 _pid) external {}

  function getFairLaunchPoolId() external returns (uint256) {
    require(_dummy>=0);
    _dummy = 1;
    return 0;
  }

  function poolInfo(uint256 _pid)
    external
    view
    returns (
      address,
      uint256,
      uint256,
      uint256,
      uint256
    ) {
        require(_pid>=0);
        require(_dummy>=0);
        return (address(0), 0, 0, 0, 0);
    }

  function alpaca() external returns (address) {
    _dummy = 1;
    return address(0);
  }

  function userInfo(uint256 _pid, address _user)
    external
    view
    returns (
      uint256,
      uint256,
      uint256,
      address
    ) {
        require(_dummy>=0);
        require(_pid>=0);
        require(_user != address(0));
        return (0, 0, 0, address(0));
    }

  function emergencyWithdraw(uint256 _pid) external {}
}

contract MockBUSD is MockERC20Upgradeable {}

contract MockAlpaca is MockERC20Upgradeable {}
