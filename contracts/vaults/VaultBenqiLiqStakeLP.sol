// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_VaultBaseLiqStakeLP.sol";

import "./actions/VaultActionsBenqiLiqStakeLP.sol";

/// @title Vault contract for Benqi liquid staking + LP strategy
contract VaultBenqiLiqStakeLP is VaultBaseLiqStakeLP {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;
    using SafeMathUpgradeable for uint256;
    using SafeSwapUni for IAMMRouter02;

    /* Functions */

    /// @notice Deposits liquid stake on Benqi protocol
    /// @param _amount The amount of AVAX to liquid stake
    function _liquidStake(uint256 _amount) internal override whenNotPaused {
        // Allow spending
        IERC20Upgradeable(token0Address).safeIncreaseAllowance(
            vaultActions,
            _amount
        );

        // Stake
        VaultActionsBenqiLiqStakeLP(vaultActions).liquidStake(
            _amount,
            token0Address,
            liquidStakeToken,
            liquidStakingPool
        );
    }

    /// @notice Withdraws liquid stake on Benqi protocol
    /// @param _amount The amount of AVAX to unstake
    function _liquidUnstake(uint256 _amount) internal override whenNotPaused {
        VaultActionsBenqiLiqStakeLP(vaultActions).liquidUnstake(
            SafeSwapUni.SafeSwapParams({
                amountIn: _amount,
                priceToken0: liquidStakeTokenPriceFeed.getExchangeRate(),
                priceToken1: token0PriceFeed.getExchangeRate(),
                token0: liquidStakeToken,
                token1: token0Address,
                maxMarketMovementAllowed: maxMarketMovementAllowed,
                path: liquidStakeToToken0Path,
                destination: address(this)
            })
        );
    }
}

contract VaultBenqiAVAXLiqStakeLP is VaultBenqiLiqStakeLP {}
