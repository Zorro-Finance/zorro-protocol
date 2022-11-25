// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../../vaults/actions/_VaultActions.sol";

import "./IVault.sol";

// TODO: Create one of these for each vault
// TODO: Hygiene - group all Vault interfaces into their own directory
// TODO: For all of these, make sure the Vaults conform to the IVault child, not just IVault

/* For interacting with our own Vaults */
interface IVaultStargate is IVault {
    /* Structs */

    struct VaultStargateInit {
        uint256 pid;
        bool isHomeChain;
        bool isFarmable;
        VaultActions.VaultAddresses keyAddresses;
        VaultActions.VaultFees fees;
        VaultActions.VaultPriceFeeds priceFeeds;
        address tokenSTG;
        address stargateRouter;
        uint16 stargatePoolId;
    }

    /* Functions */

    // Config variables
    function stargateRouter() external view returns (address);
    function stargatePoolId() external view returns (uint16);
}
