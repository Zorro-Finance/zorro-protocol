// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../../vaults/actions/_VaultActions.sol";

import "./IVault.sol";

/* For interacting with our own Vaults */
interface IVaultLiqStakeLP is IVault {
    /* Structs */

    struct VaultBaseLiqStakeLPInit {
        VaultBaseInit baseInit;
        address liquidStakeToken;
        address liquidStakingPool;
        address liquidStakeTokenPriceFeed;
        address[] liquidStakeToToken0Path;
        bool isLPFarmable;
    }

    /* Functions */

    // Config variables
    function liquidStakeToken() external view returns (address);
    function liquidStakingPool() external view returns (address);
    function lpToken() external view returns (address);
    function isLPFarmable() external view returns (bool);
}
