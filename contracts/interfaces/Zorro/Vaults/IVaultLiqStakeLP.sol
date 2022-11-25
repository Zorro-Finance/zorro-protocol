// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../../vaults/actions/_VaultActions.sol";

import "./IVault.sol";

/* For interacting with our own Vaults */
interface IVaultLiqStakeLP is IVault {
    /* Structs */

    struct VaultBaseLiqStakeLPInit {
        uint256 pid;
        bool isHomeChain;
        bool isFarmable;
        VaultActions.VaultAddresses keyAddresses;
        address liquidStakeToken;
        address liquidStakingPool;
        address[] earnedToZORROPath;
        address[] earnedToToken0Path;
        address[] stablecoinToToken0Path;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToStablecoinPath;
        address[] stablecoinToZORROPath;
        address[] stablecoinToLPPoolOtherTokenPath;
        address[] liquidStakeToToken0Path;
        VaultActions.VaultFees fees;
        VaultBaseLiqStakeLPPriceFeeds priceFeeds;
        uint256 maxMarketMovementAllowed;
    }

    struct VaultBaseLiqStakeLPPriceFeeds {
        address token0PriceFeed;
        address earnTokenPriceFeed;
        address ZORPriceFeed;
        address lpPoolOtherTokenPriceFeed;
        address stablecoinPriceFeed;
        address liquidStakeTokenPriceFeed;
    }

    /* Functions */

    // Config variables
    function liquidStakeToken() external view returns (address);
    function liquidStakingPool() external view returns (address);
}
