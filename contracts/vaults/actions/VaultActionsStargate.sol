// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/Stargate/IStargateRouter.sol";

import "../../interfaces/Stargate/IStargateLPStaking.sol";

import "../../interfaces/Zorro/Vaults/IVaultStargate.sol";

import "../../interfaces/Zorro/Vaults/Actions/IVaultActionsStargate.sol";

import "./_VaultActions.sol";

contract VaultActionsStargate is IVaultActionsStargate, VaultActions {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Functions */

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
        IVaultStargate _vault = IVaultStargate(_vaultAddr);
        address _token0 = _vault.token0Address(); // Underlying token
        address _sgPoolAddr = _vault.poolAddress(); // Stargate LP Pool address

        // Get balance of Token0
        uint256 _balToken0 = IERC20Upgradeable(_token0).balanceOf(_vaultAddr);

        // Get balance of LP token
        uint256 _balLPToken = IERC20Upgradeable(_vault.wantAddress()).balanceOf(
            _sgPoolAddr
        );

        // Rebase balance of LP token in Token0 units
        uint256 _balLPTokenInToken0 = (_balLPToken *
            IERC20Upgradeable(_token0).balanceOf(_sgPoolAddr)) /
            IERC20Upgradeable(_sgPoolAddr).totalSupply();

        // Get Earn and rebase equity into Token0 units
        uint256 _pendingEarnToken0 = (IStargateLPStaking(_sgPoolAddr)
            .pendingStargate(_vault.pid(), _vaultAddr) *
            _vault.priceFeeds(_vault.earnedAddress()).getExchangeRate()) /
            _vault.priceFeeds(_token0).getExchangeRate();

        // Sum equities
        positionVal = _balToken0 + _balLPTokenInToken0 + _pendingEarnToken0;
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

        if (_token0Address != _stablecoin) {
            // Get Token0 balance
            uint256 _token0Bal = IERC20Upgradeable(_token0Address).balanceOf(
                address(this)
            );

            // Swap Token0 -> USD
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
}
