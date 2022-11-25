// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../../vaults/actions/_VaultActions.sol";

import "./IVault.sol";

interface IVaultLending is IVault {
    /* Structs */

    struct VaultLendingInit {
        uint256 pid;
        bool isHomeChain;
        VaultActions.VaultAddresses keyAddresses;
        uint256 targetBorrowLimit;
        uint256 targetBorrowLimitHysteresis;
        address[] earnedToZORROPath;
        address[] earnedToToken0Path;
        address[] stablecoinToToken0Path;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToStablecoinPath;
        address[] stablecoinToZORROPath;
        address[] stablecoinToLPPoolOtherTokenPath;
        VaultActions.VaultFees fees;
        VaultActions.VaultPriceFeeds priceFeeds;
        address comptrollerAddress;
    }

    /* Functions */

    // Config variables
    function targetBorrowLimit() external view returns (uint256);
    function targetBorrowLimitHysteresis() external view returns (uint256);
    function comptrollerAddress() external view returns (address);
}
