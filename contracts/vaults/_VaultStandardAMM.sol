// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "../interfaces/Uniswap/IAMMFarm.sol";

import "../interfaces/Zorro/Vaults/IVaultStandardAMM.sol";

import "./actions/_VaultActionsStandardAMM.sol";

import "./_VaultBase.sol";

/// @title VaultStandardAMM: abstract base class for all PancakeSwap style AMM contracts. Maximizes yield in AMM.
abstract contract VaultStandardAMM is IVaultStandardAMM, VaultBase {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */

    /// @notice Upgradeable constructor
    /// @param _initValue A VaultStandardAMMInit struct with all constructor params
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultStandardAMMInit memory _initValue
    ) public initializer {
        // Vault config
        isLPFarmable = _initValue.isLPFarmable;

        // Super call
        _initialize(_timelockOwner, _initValue.baseInit);
    }

    /* State */

    bool public isLPFarmable; // If true, will farm LP tokens

    /* Setters */

    function setIsFarmable(bool _isFarmable) external onlyOwner {
        isLPFarmable = _isFarmable;
    }

    /* Investment Actions */

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
    function _farm() internal override {
        if (isLPFarmable) {
            // Get the Want token stored on this contract
            uint256 wantBal = IERC20Upgradeable(wantAddress).balanceOf(
                address(this)
            );

            // Allow the farm contract (e.g. MasterChef/MasterApe) the ability to transfer up to the Want amount
            IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
                farmContractAddress,
                wantBal
            );

            // Deposit the Want tokens in the Farm contract for the appropriate pool ID (PID)
            IAMMFarm(farmContractAddress).deposit(pid, wantBal);
        }
    }

    /// @notice Internal function for unfarming Want token. Responsible for unstaking Want token from MasterChef/MasterApe contracts
    /// @param _wantAmt the amount of Want tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _wantAmt) internal override {
        if (isLPFarmable) {
            // Withdraw the Want tokens from the Farm contract pool
            IAMMFarm(farmContractAddress).withdraw(pid, _wantAmt);
        }
    }

    /* Abstract Functions */

    /// @notice Fetches the pending rewards from the underlying protocol's MasterChef contract
    /// @dev Every protocol has a different function name for this, so the implementing contract must conform to this abstraction
    /// @return pendingRewards The quantity of rewards tokens available for harvest
    function pendingFarmRewards() public view virtual returns (uint256 pendingRewards);
}

import "../interfaces/PancakeSwap/IMasterChef.sol"; 

contract PCS_ZOR_BNB is VaultStandardAMM {
    function pendingFarmRewards() public view override returns (uint256 pendingRewards) {
        pendingRewards = IPCSMasterChef(farmContractAddress).pendingCake(pid, address(this));
    }
}
