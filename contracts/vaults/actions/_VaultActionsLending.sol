// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../interfaces/Lending/ILendingToken.sol";

import "../../interfaces/Zorro/Vaults/IVaultLending.sol";

import "./_VaultActions.sol";

abstract contract VaultActionsLending is VaultActions {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Functions */

    /// @notice Measures the current (unrealized) position value (measured in Want token) of the provided vault
    /// @param _vault The vault address
    /// @return positionVal Position value, in units of Want token
    function currentWantEquity(address _vault)
        public
        view
        override
        returns (uint256 positionVal)
    {
        // TODO: Fill
    }

    /// @notice Calculates accumulated unrealized profits on a vault
    /// @param _vault The vault address
    /// @return accumulatedProfit Amount of unrealized profit accumulated on the vault (not accounting for past harvests)
    /// @return harvestableProfit Amount of immediately harvestable profits
    function unrealizedProfits(address _vault)
        public
        view
        override
        returns (uint256 accumulatedProfit, uint256 harvestableProfit)
    {
        // TODO: Fill
    }

    /// @notice Performs necessary operations to convert USD into Want token
    /// @param _amountUSD The USD quantity to exchange (must already be deposited)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return wantObtained Amount of Want token obtained
    function _exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) internal override returns (uint256 wantObtained) {
        // Prep
        IVault _vault = IVault(_msgSender());
        address _stablecoin = _vault.defaultStablecoin();
        address _token0Address = _vault.token0Address();

        // Swap USD for token0
        // Single asset. Swap from USD directly to Token0
        if (_token0Address != _stablecoin) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _amountUSD,
                    priceToken0: _vault.priceFeeds(_stablecoin).getExchangeRate(),
                    priceToken1: _vault.priceFeeds(_token0Address).getExchangeRate(),
                    token0: _stablecoin,
                    token1: _token0Address,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _getSwapPath(_stablecoin, _token0Address),
                    destination: address(this)
                })
            );
        }

        // Get new Token0 balance
        wantObtained = IERC20Upgradeable(_token0Address).balanceOf(
            address(this)
        );
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal
    /// @param _amount The Want token quantity to exchange (must be deposited beforehand)
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return usdObtained Amount of USD token obtained
    function _exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) internal override returns (uint256 usdObtained) {
        // Prep
        IVault _vault = IVault(_msgSender());
        address _stablecoin = _vault.defaultStablecoin();
        address _token0Address = _vault.token0Address();

        // Swap Token0 -> USD
        if (_token0Address != _stablecoin) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _amount,
                    priceToken0: _vault.priceFeeds(_token0Address).getExchangeRate(),
                    priceToken1: _vault.priceFeeds(_stablecoin).getExchangeRate(),
                    token0: _token0Address,
                    token1: _stablecoin,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _getSwapPath(_token0Address, _stablecoin),
                    destination: address(this)
                })
            );
        }

        // Calculate USD balance
        usdObtained = IERC20Upgradeable(_stablecoin).balanceOf(
            address(this)
        );
    }

    /* Utilities */

    /// @notice Gets loan collateral factor from lending protocol
    function collateralFactor(address _comptrollerAddress, address _poolAddress)
        public
        view
        virtual
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
        x = _ox - _withdrawAmt;
        // Calc init borrow balance
        y = ILendingToken(_poolAddress).borrowBalanceCurrent(address(this));
        // Get collateral factor from protocol
        c = this.collateralFactor(_comptrollerAddress, _poolAddress);
        // Target leverage
        targetL = (c * _targetBorrowLimit) / 1e18;
        // Current leverage = borrow / supply
        currentL = (y * 1e18) / x;
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
        dy =
            (((_targetLeverage * _x) / 1e18) - _y * 1e18) /
            (uint256(1e18) - _targetLeverage);

        // Cap incremental borrow to init supply * collateral fact % - curr borrowed
        uint256 _max_dy = ((_ox * _c) / 1e18) - _y;
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
        dy =
            ((_y - ((_targetLeverage * _x) / 1e18)) * 1e18) /
            (uint256(1e18) - _targetLeverage);

        // Cap incremental borrow-repay to init supply - (curr borrowed / collateral fact %)
        uint256 _max_dy = _ox - ((_y * 1e18) / _c);
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
        uint256 _borrowBal = ILendingToken(_poolAddress).borrowBalanceCurrent(
            _vault
        );
        amtLocked = _wantBal + _supplyBal - _borrowBal;
    }
}
