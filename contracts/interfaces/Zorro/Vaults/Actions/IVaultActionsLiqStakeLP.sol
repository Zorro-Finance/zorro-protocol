// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IVaultActions.sol";

interface IVaultActionsLiqStakeLP is IVaultActions {
    /* Structs */

    struct StakeLiqTokenInLPPoolParams {
        address liquidStakeToken;
        address nativeToken;
        AggregatorV3Interface liquidStakeTokenPriceFeed;
        AggregatorV3Interface nativeTokenPriceFeed;
        address[] liquidStakeToNativePath;
    }

    struct UnstakeLiqTokenFromLPPoolParams {
        address liquidStakeToken;
        address nativeToken;
        address lpPoolToken;
        AggregatorV3Interface liquidStakeTokenPriceFeed;
        AggregatorV3Interface nativeTokenPriceFeed;
        address[] nativeToLiquidStakePath;
    }

    /* Functions */

    function liquidStake(
        uint256 _amount,
        address _token0,
        address _liqStakeToken,
        address _liqStakePool
    ) external;

    function liquidUnstake(SafeSwapUni.SafeSwapParams memory _swapParams)
        external;

    function stakeInLPPool(
        uint256 _amount,
        StakeLiqTokenInLPPoolParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) external;
}
