// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/Uniswap/IAMMFarm.sol";

import "../interfaces/Zorro/Vaults/IVaultLiqStakeLP.sol";

import "../interfaces/Zorro/Vaults/Actions/IVaultActions.sol";

import "./actions/_VaultActionsLiqStakeLP.sol";

import "./_VaultBase.sol";

/// @title Vault base contract for liquid staking + LP strategy
abstract contract VaultBaseLiqStakeLP is IVaultLiqStakeLP, VaultBase {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */

    /// @notice Upgradeable constructor
    /// @param _initValue A VaultAlpacaInit struct containing all init values
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultBaseLiqStakeLPInit memory _initValue
    ) public initializer {
        // Super call
        _initialize(_timelockOwner, _initValue.baseInit);

        // Addresses
        liquidStakeToken = _initValue.liquidStakeToken;
        liquidStakingPool = _initValue.liquidStakingPool;

        // Vault config
        isLPFarmable = _initValue.isLPFarmable;

        // Swap paths
        _setSwapPaths(_initValue.liquidStakeToToken0Path);
        _setSwapPaths(
            IVaultActions(vaultActions).reversePath(
                _initValue.liquidStakeToToken0Path
            )
        );

        // Price feeds
        _setPriceFeed(liquidStakeToken, _initValue.liquidStakeTokenPriceFeed);
    }

    /* State */

    address public liquidStakeToken; // Synth token for liquid staking (e.g. sETH)
    address public liquidStakingPool; // Liquid staking pool (can sometimes be the same as liquidStakeToken)
    address public lpToken; // LP token that includes liquidStakeToken and token0Address
    AggregatorV3Interface public liquidStakeTokenPriceFeed; // Price feed for sETH
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

    /// @notice Internal function for farming
    function _farm() internal override {
        // Calculate balance
        uint256 _token0Bal = IERC20Upgradeable(token0Address).balanceOf(
            address(this)
        );

        // Approve spending
        IERC20Upgradeable(token0Address).safeIncreaseAllowance(
            vaultActions,
            _token0Bal
        );

        // Perform liquid stake and add liquidity, sending LP token back to this address
        IVaultActionsLiqStakeLP(vaultActions).liquidStakeAndAddLiq(
            _token0Bal,
            token0Address,
            liquidStakeToken,
            liquidStakingPool,
            maxMarketMovementAllowed
        );

        // Deposit the Want tokens in the Farm contract for the appropriate pool ID (PID) IF AMM Masterchef allocates rewards
        if (isLPFarmable) {
            // Get the LP token stored on this contract
            uint256 _lpBal = IERC20Upgradeable(poolAddress).balanceOf(
                address(this)
            );

            // Allow the farm contract (e.g. MasterChef/MasterApe) the ability to transfer up to the Want amount
            IERC20Upgradeable(poolAddress).safeIncreaseAllowance(
                farmContractAddress,
                _lpBal
            );

            // Farm
            IAMMFarm(farmContractAddress).deposit(pid, _lpBal);
        }
    }

    /// @notice Internal function for unfarming LP token.
    /// @param _amount the amount of earned tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _amount) internal override {
        // Withdraw the LP tokens from the Farm contract pool (IF AMM Masterchef allocates rewards)
        if (isLPFarmable) {
            IAMMFarm(farmContractAddress).withdraw(pid, _amount);
        }

        // Calc balance
        uint256 _balLPToken = IERC20Upgradeable(poolAddress).balanceOf(
            address(this)
        );

        // Approve spending
        IERC20Upgradeable(poolAddress).safeIncreaseAllowance(
            vaultActions,
            _balLPToken
        );

        // Remove liquidity from LP pool and unstake sETH
        IVaultActionsLiqStakeLP(vaultActions).removeLiqAndliquidUnstake(
            _balLPToken,
            token0Address,
            liquidStakeToken,
            poolAddress,
            maxMarketMovementAllowed
        );
    }

    /* Abstract Functions */

    /// @notice Fetches the pending rewards from the underlying protocol's MasterChef contract
    /// @dev Every protocol has a different function name for this, so the implementing contract must conform to this abstraction
    /// @return pendingRewards The quantity of rewards tokens available for harvest
    function pendingLPFarmRewards() public view virtual returns (uint256 pendingRewards);
}