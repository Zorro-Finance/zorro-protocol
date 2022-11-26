// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../../vaults/actions/_VaultActions.sol";

import "./IVault.sol";

/* For interacting with our own Vaults */
interface IVaultAlpaca is IVault {
    /* Structs */

    struct VaultAlpacaInit {
        uint256 pid;
        bool isHomeChain;
        bool isFarmable;
        VaultActions.VaultAddresses keyAddresses;
        address[] earnedToZORROPath;
        address[] earnedToToken0Path;
        address[] stablecoinToToken0Path;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToStablecoinPath;
        address[] stablecoinToZORROPath;
        address[] stablecoinToLPPoolOtherTokenPath;
        VaultActions.VaultFees fees;
        VaultActions.VaultPriceFeeds priceFeeds;
    }
}
