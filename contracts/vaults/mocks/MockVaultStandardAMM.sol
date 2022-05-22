// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../VaultStandardAMM.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "../../tokens/mocks/MockToken.sol";

contract MockVaultFactoryStandardAMM is VaultFactoryStandardAMM {}

contract MockVaultStandardAMM is VaultStandardAMM {
    function reversePath(address[] memory _path)
        public
        pure
        returns (address[] memory)
    {
        return _reversePath(_path);
    }

    function unfarm(uint256 _wantAmt) public {
        _unfarm(_wantAmt);
    }

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

contract MockAMMFarm is IAMMFarm, MockERC20Upgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public burnAddress;
    address public wantToken;

    function setWantAddress(address _wantToken) public {
        wantToken = _wantToken;
    }

    function setBurnAddress(address _burnAddress) public {
        burnAddress = _burnAddress;
    }

    function poolLength() external view returns (uint256) {}

    function userInfo() external view returns (uint256) {}

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        external
        view
        returns (uint256)
    {}

    // View function to see pending CAKEs on frontend.
    function pendingCake(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {}

    event Deposited(uint256 indexed _pid, uint256 indexed _amount);

    // Deposit LP tokens to MasterChef for CAKE allocation.
    function deposit(uint256 _pid, uint256 _amount) external {
        IERC20Upgradeable(wantToken).safeTransferFrom(msg.sender, burnAddress, _amount);
        emit Deposited(_pid, _amount);
    }

    event Withdrew(uint256 indexed _pid, uint256 indexed _amount);

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external {
        IMockERC20Upgradeable(wantToken).mint(msg.sender, _amount);
        emit Withdrew(_pid, _amount);
    }

    // Stake CAKE tokens to MasterChef
    function enterStaking(uint256 _amount) external {}

    // Withdraw CAKE tokens from STAKING.
    function leaveStaking(uint256 _amount) external {}

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external {}
}

contract MockAMMToken0 is MockERC20Upgradeable {}
contract MockAMMToken1 is MockERC20Upgradeable {}
contract MockAMMOtherLPToken is MockERC20Upgradeable {}
contract MockLPPool is MockERC20Upgradeable {}
contract MockLPPool1 is MockLPPool {}
