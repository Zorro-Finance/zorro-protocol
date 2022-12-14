// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../../vaults/actions/_VaultActions.sol";

import "./IVault.sol";

interface IVaultStandardAMM is IVault {
    /* Structs */

    struct VaultStandardAMMInit {
        VaultBaseInit baseInit;
        bool isLPFarmable;
    }
}
