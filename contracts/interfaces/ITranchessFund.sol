// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/* For interacting with Tranchess Fund */
interface ITranchessFund {
    function getRebalanceSize() external view returns (uint256);
}