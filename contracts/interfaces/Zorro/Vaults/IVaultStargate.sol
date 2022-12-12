// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../../vaults/actions/_VaultActions.sol";

import "./IVault.sol";

interface IVaultStargate is IVault {
    /* Structs */

    struct VaultStargateInit {
        VaultBaseInit baseInit;
        address stargateRouter;
        uint16 stargatePoolId;
    }

    /* Functions */

    // Config variables
    function stargateRouter() external view returns (address);
    function stargatePoolId() external view returns (uint16);
}
