// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/Uniswap/IAMMFarm.sol";

import "../interfaces/Zorro/Vaults/IVaultLiqStakeLP.sol";

import "./actions/_VaultActionsLiqStakeLP.sol";

import "./_VaultBase.sol";

/// @title Vault base contract for liquid staking + LP strategy
contract VaultBaseLiqStakeLP is IVaultLiqStakeLP, VaultBase {
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
        // Addresses
        liquidStakeToken = _initValue.liquidStakeToken;
        liquidStakingPool = _initValue.liquidStakingPool;

        // Swap paths
        _setSwapPaths(_initValue.liquidStakeToToken0Path);
        _setSwapPaths(
            IVaultActions(vaultActions).reversePath(
                _initValue.liquidStakeToToken0Path
            )
        );

        // Price feeds
        _setPriceFeed(liquidStakeToken, _initValue.liquidStakeTokenPriceFeed);

        // Super call
        VaultBase.initialize(_timelockOwner, _initValue.baseInit);
    }

    /* State */

    address public liquidStakeToken; // Synth token for liquid staking (e.g. sETH)
    address public liquidStakingPool; // Liquid staking pool (can sometimes be the same as liquidStakeToken)
    address public lpToken; // LP token that includes liquidStakeToken and token0Address
    AggregatorV3Interface public liquidStakeTokenPriceFeed; // Price feed for sETH

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

        // Stake ETH (liquid staking)
        IVaultActionsLiqStakeLP(vaultActions).liquidStake(
            _token0Bal,
            token0Address,
            liquidStakeToken,
            liquidStakingPool
        );

        // Calc balance of sETH on this contract
        uint256 _synthBal = IERC20Upgradeable(liquidStakeToken).balanceOf(
            address(this)
        );

        // Approve spending
        IERC20Upgradeable(liquidStakeToken).safeIncreaseAllowance(
            vaultActions,
            _synthBal
        );

        // Swap 1/2 sETH, to ETH and add liquidity to an LP Pool (sends LP token back to this address)
        IVaultActionsLiqStakeLP(vaultActions).stakeInLPPool(
            _synthBal,
            IVaultActionsLiqStakeLP.StakeLiqTokenInLPPoolParams({
                liquidStakeToken: liquidStakeToken,
                nativeToken: token0Address,
                liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                nativeTokenPriceFeed: priceFeeds[token0Address],
                liquidStakeToNativePath: swapPaths[liquidStakeToken][
                    token0Address
                ]
            }),
            maxMarketMovementAllowed
        );

        // Deposit the Want tokens in the Farm contract for the appropriate pool ID (PID) IF AMM Masterchef allocates rewards
        if (isFarmable) {
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
        if (isFarmable) {
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

        // TODO: The next few funcs involve a lot of back and forth
        // between actions and vault. To save gas fees it may make sense
        // to combine these all into actions

        // Exit LP pool and get back sETH, WETH
        IVaultActionsLiqStakeLP(vaultActions).exitPool(
            _amount,
            maxMarketMovementAllowed,
            address(this),
            IVaultActions.ExitPoolParams({
                token0: liquidStakeToken,
                token1: token0Address,
                poolAddress: poolAddress,
                lpTokenAddress: poolAddress
            })
        );

        // Calc sETH balance
        uint256 _synthTokenBal = IERC20Upgradeable(liquidStakeToken).balanceOf(
            address(this)
        );

        // Approve spending
        IERC20Upgradeable(liquidStakeToken).safeIncreaseAllowance(
            vaultActions,
            _synthTokenBal
        );

        // Unstake sETH to get ETH
        IVaultActionsLiqStakeLP(vaultActions).liquidUnstake(
            SafeSwapUni.SafeSwapParams({
                amountIn: _synthTokenBal,
                priceToken0: priceFeeds[liquidStakeToken].getExchangeRate(),
                priceToken1: priceFeeds[token0Address].getExchangeRate(),
                token0: liquidStakeToken,
                token1: token0Address,
                maxMarketMovementAllowed: maxMarketMovementAllowed,
                path: swapPaths[liquidStakeToken][token0Address],
                destination: address(this)
            })
        );
    }
}

contract VaultAnkrBNBLiqStakeLP is VaultBaseLiqStakeLP {}

contract VaultBenqiAVAXLiqStakeLP is VaultBaseLiqStakeLP {}
