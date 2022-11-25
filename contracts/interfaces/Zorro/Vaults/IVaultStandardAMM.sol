// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../../vaults/actions/_VaultActions.sol";

import "./IVault.sol";

interface IVaultStandardAMM is IVault {
    /* Structs */

    struct VaultStandardAMMInit {
        uint256 pid;
        bool isHomeChain;
        bool isFarmable;
        VaultActions.VaultAddresses keyAddresses;
        address[] earnedToZORROPath;
        address[] earnedToToken0Path;
        address[] earnedToToken1Path;
        address[] stablecoinToToken0Path;
        address[] stablecoinToToken1Path;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToStablecoinPath;
        VaultActions.VaultFees fees;
        VaultActions.VaultPriceFeeds priceFeeds;
    }
}
