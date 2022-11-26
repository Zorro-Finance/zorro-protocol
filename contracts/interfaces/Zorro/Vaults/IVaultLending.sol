// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../../vaults/actions/_VaultActions.sol";

import "./IVault.sol";

interface IVaultLending is IVault {
    /* Structs */

    struct VaultLendingInit {
        VaultBaseInit baseInit;
        uint256 targetBorrowLimit;
        uint256 targetBorrowLimitHysteresis;
        address comptrollerAddress;
    }

    /* Functions */

    // Config variables
    function targetBorrowLimit() external view returns (uint256);
    function targetBorrowLimitHysteresis() external view returns (uint256);
    function comptrollerAddress() external view returns (address);
}
