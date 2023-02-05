// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/Zorro/Vaults/IVaultAlpaca.sol";

import "./actions/VaultActionsAlpaca.sol";

import "./_VaultBase.sol";

/// @title Vault contract for Alpaca strategies
contract VaultAlpaca is IVaultAlpaca, VaultBase {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */

    /// @notice Upgradeable constructor
    /// @param _timelockOwner The designated timelock controller address to act as owner
    /// @param _initValue A VaultAlpacaInit struct containing all init values
    function initialize(
        address _timelockOwner,
        VaultAlpacaInit memory _initValue
    ) public initializer {
        // Super call
        _initialize(_timelockOwner, _initValue.baseInit);

        // Addresses
        lendingToken = _initValue.lendingToken;
    }

    /* State */

    address public lendingToken; // Lending token exchanged for supplying underlying asset (e.g. vToken)

    /* Setters */

    function setLendingToken(address _lendingToken) external onlyOwner {
        lendingToken = _lendingToken;
    }

    /* Investment Actions */

    /// @notice Public function for farming Want token.
    function farm() public virtual nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
    function _farm() internal override {
        // Get the Want token stored on this contract
        uint256 _wantAmt = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );

        // Increase allowance
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            poolAddress,
            _wantAmt
        );

        // Deposit token to get Want token
        IAlpacaVault(poolAddress).deposit(_wantAmt);

        // Calculate resulting lending token balance
        uint256 _lendingTokenBal = IERC20Upgradeable(lendingToken).balanceOf(
            address(this)
        );

        // Allow the farm contract (e.g. MasterChef) the ability to transfer up to the Want amount
        IERC20Upgradeable(lendingToken).safeIncreaseAllowance(
            farmContractAddress,
            _lendingTokenBal
        );

        // Deposit the Want tokens in the Farm contract
        IFairLaunch(farmContractAddress).deposit(address(this), pid, _wantAmt);
    }

    /// @notice Internal function for unfarming Want token. Responsible for unstaking Want token from MasterChef/MasterApe contracts
    /// @param _wantAmt the amount of Want tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _wantAmt) internal override {
        // Withdraw tokens from the Farm contract
        IFairLaunch(farmContractAddress).withdraw(address(this), pid, _wantAmt);

        // Get balance
        uint256 _lendingBal = IERC20Upgradeable(lendingToken).balanceOf(address(this));

        // Approve
        IERC20Upgradeable(lendingToken).safeIncreaseAllowance(
            poolAddress,
            _lendingBal
        );

        // Withdraw lending token to get Token0
        IAlpacaVault(poolAddress).withdraw(_lendingBal);
    }
}

contract VaultAlpacaBNB is VaultAlpaca {}