// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "../../interfaces/Lending/ILendingToken.sol";

import "./_VaultActions.sol";

abstract contract VaultActionsLending is VaultActions {
    /* Libraries */

    using SafeMathUpgradeable for uint256;

    /* Utilities */

    /// @notice Gets loan collateral factor from lending protocol
    function collateralFactor(address _comptrollerAddress, address _poolAddress)
        public
        virtual
        view
        returns (uint256 collFactor);

    /// @notice Calculates leveraged lending parameters for supply/borrow rebalancing
    /// @param _withdrawAmt Amount to withdraw
    /// @param _ox Raw supply (before any withdrawal)
    /// @param _comptrollerAddress Address of protocol comptroller
    /// @param _poolAddress Address of lending pool
    /// @param _targetBorrowLimit Target borrow %
    /// @return x Adjusted supply (accounts amount to withdraw)
    /// @return y Amount borrowed
    /// @return c Collateral factor
    /// @return targetL Target leverage threshold
    /// @return currentL Current leverage
    /// @return liquidityAvailable Total liquidity avaialble in pool
    function levLendingParams(
        uint256 _withdrawAmt,
        uint256 _ox,
        address _comptrollerAddress,
        address _poolAddress,
        uint256 _targetBorrowLimit
    )
        public
        returns (
            uint256 x,
            uint256 y,
            uint256 c,
            uint256 targetL,
            uint256 currentL,
            uint256 liquidityAvailable
        )
    {
        // Adjusted supply = init supply - amt to withdraw
        x = _ox.sub(_withdrawAmt);
        // Calc init borrow balance
        y = ILendingToken(_poolAddress).borrowBalanceCurrent(address(this));
        // Get collateral factor from protocol
        c = this.collateralFactor(_comptrollerAddress, _poolAddress);
        // Target leverage
        targetL = c.mul(_targetBorrowLimit).div(1e18);
        // Current leverage = borrow / supply
        currentL = y.mul(1e18).div(x);
        // Liquidity (of underlying) available in the pool overall
        liquidityAvailable = ILendingToken(_poolAddress).getCash();
    }

    /// @notice Calculates incremental borrow amount (_dy) when below leverage target hysteresis envelope
    /// @param _x Supply amount
    /// @param _y Borrow amount
    /// @param _ox Initial supply (gross of withdrawal amount)
    /// @param _c Collateral factor
    /// @param _targetLeverage Target leverage amount
    /// @param _liquidityAvailable Liquidity available in underlying pool
    /// @return dy The incremental amount to be borrowed
    function calcIncBorrowBelowTarget(
        uint256 _x,
        uint256 _y,
        uint256 _ox,
        uint256 _c,
        uint256 _targetLeverage,
        uint256 _liquidityAvailable
    ) public pure returns (uint256 dy) {
        // (Target lev % * curr supply - curr borrowed)/(1 - Target lev %)
        dy = _targetLeverage.mul(_x).div(1e18).sub(_y).mul(1e18).div(
            uint256(1e18).sub(_targetLeverage)
        );

        // Cap incremental borrow to init supply * collateral fact % - curr borrowed
        uint256 _max_dy = _ox.mul(_c).div(1e18).sub(_y);
        if (dy > _max_dy) dy = _max_dy;

        // Also cap to max liq available
        if (dy > _liquidityAvailable) dy = _liquidityAvailable;
    }

    /// @notice Calculates incremental borrow amount (_dy) when above leverage target hysteresis envelope
    /// @param _x Supply amount
    /// @param _y Borrow amount
    /// @param _ox Initial supply (gross of withdrawal amount)
    /// @param _c Collateral factor
    /// @param _targetLeverage Target leverage amount
    /// @param _liquidityAvailable Liquidity available in underlying pool
    /// @return dy The incremental amount to be borrowed
    function calcIncBorrowAboveTarget(
        uint256 _x,
        uint256 _y,
        uint256 _ox,
        uint256 _c,
        uint256 _targetLeverage,
        uint256 _liquidityAvailable
    ) public pure returns (uint256 dy) {
        // (Curr borrowed - (Target lev % * Curr supply)) / (1 - Target lev %)
        dy = _y.sub(_targetLeverage.mul(_x).div(1e18)).mul(1e18).div(
            uint256(1e18).sub(_targetLeverage)
        );

        // Cap incremental borrow-repay to init supply - (curr borrowed / collateral fact %)
        uint256 _max_dy = _ox.sub(_y.mul(1e18).div(_c));
        if (dy > _max_dy) dy = _max_dy;

        // Also cap to max liq available
        if (dy > _liquidityAvailable) dy = _liquidityAvailable;
    }

    /// @notice Calc want token locked, accounting for leveraged supply/borrow
    /// @param _vault The vault to check balances of
    /// @param _tokenAddress The address of the underlying token
    /// @param _poolAddress The address of the lending pool
    /// @return amtLocked The adjusted wantLockedTotal quantity
    function wantTokenLockedAdj(
        address _vault,
        address _tokenAddress,
        address _poolAddress
    ) public returns (uint256 amtLocked) {
        uint256 _wantBal = ILendingToken(_tokenAddress).balanceOf(_vault);
        uint256 _supplyBal = ILendingToken(_poolAddress).balanceOfUnderlying(
            _vault
        );
        uint256 _borrowBal = ILendingToken(_poolAddress)
            .borrowBalanceCurrent(_vault);
        amtLocked = _wantBal.add(_supplyBal).sub(_borrowBal);
    }
}
