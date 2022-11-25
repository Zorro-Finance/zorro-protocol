// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../../vaults/actions/_VaultActions.sol";

import "./IVault.sol";

interface IVaultZorro is IVault {
    /* Structs */

    struct VaultZorroInit {
        uint256 pid;
        VaultActions.VaultAddresses keyAddresses;
        address[] stablecoinToToken0Path;
        VaultActions.VaultFees fees;
        VaultActions.VaultPriceFeeds priceFeeds;
    }
}
