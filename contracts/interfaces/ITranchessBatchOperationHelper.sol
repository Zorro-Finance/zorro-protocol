// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/* For interacting with Tranchess Batch functions */
interface ITranchessBatchOperationHelper {
    function settleTrades(
        address[] calldata exchanges,
        uint256[] calldata encodedEpochs,
        address account
    ) external returns (uint256[] memory totalTokenAmounts, uint256 totalQuoteAmount);
}