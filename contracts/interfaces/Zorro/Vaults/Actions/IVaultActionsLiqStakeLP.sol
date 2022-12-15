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

    function liquidStakeAndAddLiq(
        uint256 _amount,
        address _token,
        address _liqStakeToken,
        address _liqStakePool,
        uint256 _maxMarketMovementAllowed
    ) external;

    function removeLiqAndliquidUnstake(
        uint256 _amount,
        address _nativeToken,
        address _liquidStakeToken,
        address _lpToken,
        uint256 _maxMarketMovementAllowed
    ) external;
}
