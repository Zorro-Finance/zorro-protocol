// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../interfaces/Alpaca/IAlpacaFairLaunch.sol";

import "../../interfaces/Alpaca/IAlpacaVault.sol";

import "../../interfaces/IAMMRouter02.sol";

import "../../interfaces/Zorro/Vaults/IVaultAlpaca.sol";

import "../../libraries/SafeSwap.sol";

import "../../libraries/PriceFeed.sol";

import "./_VaultActions.sol";

contract VaultActionsAlpaca is VaultActions {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /* Functions */

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
        address _pool = _vault.poolAddress();

        // Swap USD for token0
        // Single asset. Swap from USD directly to Token0
        if (_token0Address != _stablecoin) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _amountUSD,
                    priceToken0: _vault
                        .priceFeeds(_stablecoin)
                        .getExchangeRate(),
                    priceToken1: _vault
                        .priceFeeds(_token0Address)
                        .getExchangeRate(),
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

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be deposited beforehand)
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return usdObtained Amount of USD token obtained
    function _exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) internal override returns (uint256 usdObtained) {
        // Preflight checks
        require(_amount > 0, "negWant");

        // Prep
        IVault _vault = IVault(_msgSender());
        address _token0Address = _vault.token0Address();
        address _stablecoin = _vault.defaultStablecoin();

        // Get Token0 balance
        uint256 _token0Bal = IERC20Upgradeable(_token0Address).balanceOf(
            address(this)
        );

        // Swap Token0 -> USD
        if (_token0Address != _stablecoin) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _token0Bal,
                    priceToken0: _vault
                        .priceFeeds(_token0Address)
                        .getExchangeRate(),
                    priceToken1: _vault
                        .priceFeeds(_stablecoin)
                        .getExchangeRate(),
                    token0: _token0Address,
                    token1: _stablecoin,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _getSwapPath(_token0Address, _stablecoin),
                    destination: address(this)
                })
            );
        }

        // Calculate USD balance
        usdObtained = IERC20Upgradeable(_stablecoin).balanceOf(address(this));
    }

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
}
