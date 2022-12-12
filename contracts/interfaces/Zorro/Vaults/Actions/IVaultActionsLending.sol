// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IVaultActions.sol";

interface IVaultActionsLending is IVaultActions {
    /* Functions */

    function collateralFactor(address _comptrollerAddress, address _poolAddress)
        external
        view
        returns (uint256 collFactor);

    function levLendingParams(
        uint256 _withdrawAmt,
        uint256 _ox,
        address _comptrollerAddress,
        address _poolAddress,
        uint256 _targetBorrowLimit
    )
        external
        returns (
            uint256 x,
            uint256 y,
            uint256 c,
            uint256 targetL,
            uint256 currentL,
            uint256 liquidityAvailable
        );

    function calcIncBorrowBelowTarget(
        uint256 _x,
        uint256 _y,
        uint256 _ox,
        uint256 _c,
        uint256 _targetLeverage,
        uint256 _liquidityAvailable
    ) external pure returns (uint256 dy);

    function calcIncBorrowAboveTarget(
        uint256 _x,
        uint256 _y,
        uint256 _ox,
        uint256 _c,
        uint256 _targetLeverage,
        uint256 _liquidityAvailable
    ) external pure returns (uint256 dy);

    function wantTokenLockedAdj(
        address _vault,
        address _tokenAddress,
        address _poolAddress
    ) external returns (uint256 amtLocked);
}
