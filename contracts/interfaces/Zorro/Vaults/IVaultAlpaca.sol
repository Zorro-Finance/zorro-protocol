// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../../vaults/actions/_VaultActions.sol";

import "./IVault.sol";

/* For interacting with our own Vaults */
interface IVaultAlpaca is IVault {
    /* Structs */

    struct VaultAlpacaInit {
        VaultBaseInit baseInit;
        address lendingToken;
    }
}
