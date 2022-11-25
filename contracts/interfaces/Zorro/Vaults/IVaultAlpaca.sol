// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IVault.sol";

/* For interacting with our own Vaults */
interface IVaultAlpaca is IVault {
    /* Functions */

    // Config variables
    function stablecoinToZORROPath(uint256 _i) external view returns (address);
    function stablecoinToLPPoolOtherTokenPath(uint256 _i) external view returns (address);
}
