// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IVault.sol";

interface IVaultLending is IVault {
    /* Functions */

    // Config variables
    function stablecoinToZORROPath(uint256 _i) external view returns (address);
    function stablecoinToLPPoolOtherTokenPath(uint256 _i) external view returns (address);
    function targetBorrowLimit() external view returns (uint256);
    function targetBorrowLimitHysteresis() external view returns (uint256);
    function comptrollerAddress() external view returns (address);
}
