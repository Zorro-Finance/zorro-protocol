// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/* For interacting with Tranchess Exchange */
interface ITranchessExchange {
    // Queen
    function buyM(
        uint256 version,
        uint256 maxPDLevel,
        uint256 quoteAmount
    ) external;

    function sellM(
        uint256 version,
        uint256 minPDLevel,
        uint256 baseAmount
    ) external;

    // Bishop
    function buyA(
        uint256 version,
        uint256 maxPDLevel,
        uint256 quoteAmount
    ) external;

    function sellA(
        uint256 version,
        uint256 minPDLevel,
        uint256 baseAmount
    ) external;

    // Rook
    function buyB(
        uint256 version,
        uint256 maxPDLevel,
        uint256 quoteAmount
    ) external;

    function sellB(
        uint256 version,
        uint256 minPDLevel,
        uint256 baseAmount
    ) external;

    // Epoch logic
    function endOfEpoch(uint256 timestamp) external pure returns (uint256);
}