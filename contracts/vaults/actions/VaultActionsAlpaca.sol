// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../interfaces/Alpaca/IAlpacaFairLaunch.sol";

import "../../interfaces/Alpaca/IAlpacaVault.sol";

import "../../interfaces/Uniswap/IAMMRouter02.sol";

import "../../interfaces/Zorro/Vaults/IVaultAlpaca.sol";

import "../../interfaces/Zorro/Vaults/Actions/IVaultActionsAlpaca.sol";

import "../../libraries/SafeSwap.sol";

import "../../libraries/PriceFeed.sol";

import "./_VaultActions.sol";

contract VaultActionsAlpaca is IVaultActionsAlpaca, VaultActions {
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
    /// @param _vaultAddr The vault address
    /// @return positionVal Position value, in units of Want token
    function currentWantEquity(address _vaultAddr)
        public
        view
        override(IVaultActions, VaultActions)
        returns (uint256 positionVal)
    {
        // Prep
        IVaultAlpaca _vault = IVaultAlpaca(_vaultAddr);
        address _token0 = _vault.token0Address(); // Underlying token
        address _iToken = _vault.wantAddress(); // Amount of LP token (e.g. iBNB)
        address _alpaca = _vault.earnedAddress(); // Amount of farm token (ALPACA)
        AggregatorV3Interface _token0PriceFeed = _vault.priceFeeds(_token0);

        // Get balance of underlying (want)
        uint256 _balToken0 = IERC20Upgradeable(_token0).balanceOf(_vaultAddr);

        // Get balance of LP token
        uint256 _balIToken = IERC20Upgradeable(_iToken).balanceOf(_vaultAddr);

        // Express balance of LP token in Want token units
        uint256 _balITokenToken0 = _balIToken * IERC20Upgradeable(_token0).balanceOf(_iToken) / IERC20Upgradeable(_iToken).totalSupply();

        // Get pending Earn
        uint256 _pendingAlpaca = IFairLaunch(_vault.farmContractAddress()).pendingAlpaca(_vault.pid(), _vaultAddr);

        // Express Earn token quantity in Want token units
        uint256 _pendingAlpacaToken0 = _pendingAlpaca * _vault.priceFeeds(_alpaca).getExchangeRate() / _token0PriceFeed.getExchangeRate();

        // Sum up equities
        positionVal = _balToken0 + _balITokenToken0 + _pendingAlpacaToken0;
    }
}
