// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/Zorro/Vaults/IVaultStandardAMM.sol";

import "../../interfaces/Uniswap/IAMMFarm.sol";

import "../../interfaces/Zorro/Vaults/Actions/IVaultActionsStandardAMM.sol";

import "./_VaultActions.sol";

contract VaultActionsStandardAMM is IVaultActionsStandardAMM, VaultActions {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
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
        IVaultStandardAMM _vault = IVaultStandardAMM(_vaultAddr);
        address _lpToken = _vault.wantAddress();
        address _token0 = _vault.token0Address();

        // Farm activity (if applicable)
        uint256 _stakedLP;
        uint256 _pendingEarnLP;

        if (_vault.isLPFarmable()) {
            // Get balance of LP token staked on Masterchef (if isFarmable)
            (uint256 _amtLPStaked, ) = IAMMFarm(_vault.farmContractAddress())
                .userInfo(_vault.pid(), _vaultAddr);

            // Express in Token0 units
            _stakedLP =
                (_amtLPStaked *
                    IERC20Upgradeable(_token0).balanceOf(_lpToken)) /
                IERC20Upgradeable(_lpToken).totalSupply();

            // Get pending Earn
            uint256 _pendingEarn = IVaultStandardAMM(_vaultAddr)
                .pendingFarmRewards();

            // Convert to equivalent in Want token
            uint256 _earnEquityInToken0 = (_pendingEarn *
                _vault.priceFeeds(_vault.earnedAddress()).getExchangeRate()) /
                (2 * _vault.priceFeeds(_token0).getExchangeRate());

            // Calculate earn balance in units of LP (earn bal in units of Token 0 * total LP token supply / balance of token 0 on LP pool contract)
            _pendingEarnLP =
                (_earnEquityInToken0 *
                    IERC20Upgradeable(_lpToken).totalSupply()) /
                IERC20Upgradeable(_token0).balanceOf(_lpToken);
        }

        // Sum up all equity in the units of the Want token
        positionVal = _stakedLP + _pendingEarnLP;
    }

    /// @notice Performs necessary operations to convert USD into Want token and transfer back to sender
    /// @dev NOTE: Requires caller to approve spending beforehand
    /// @param _amountUSD The amount of USD to exchange for Want token (must already be deposited on this contract)
    /// @param _maxMarketMovementAllowed Slippage (990 = 1% etc.)
    /// @return wantObtained Amount of Want token obtained
    function _exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) internal override returns (uint256 wantObtained) {
        // Prep
        IVault _vault = IVault(_msgSender());
        address _stablecoin = _vault.defaultStablecoin();
        address _token0Address = _vault.token0Address();
        address _token1Address = _vault.token1Address();
        address _want = _vault.wantAddress();

        // Swap 1/2 USD for token0
        if (_token0Address != _stablecoin) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _amountUSD / 2,
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

        // Swap 1/2 USD for token1
        if (_token1Address != _stablecoin) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _amountUSD / 2,
                    priceToken0: _vault
                        .priceFeeds(_stablecoin)
                        .getExchangeRate(),
                    priceToken1: _vault
                        .priceFeeds(_token1Address)
                        .getExchangeRate(),
                    token0: _stablecoin,
                    token1: _token1Address,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _getSwapPath(_stablecoin, _token1Address),
                    destination: address(this)
                })
            );
        }

        // Deposit token0, token1 into LP pool to get Want token (i.e. LP token)
        uint256 _token0Amt = IERC20Upgradeable(_token0Address).balanceOf(
            address(this)
        );
        uint256 _token1Amt = IERC20Upgradeable(_token1Address).balanceOf(
            address(this)
        );

        // Add liquidity
        _joinPool(
            _token0Address,
            _token1Address,
            _token0Amt,
            _token1Amt,
            _maxMarketMovementAllowed,
            address(this)
        );

        // Calculate resulting want token balance
        wantObtained = IERC20Upgradeable(_want).balanceOf(address(this));
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal, transfers back to sender
    /// @param _amount The Want token quantity to exchange
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
        address _stablecoin = _vault.defaultStablecoin();
        address _token0Address = _vault.token0Address();
        address _token1Address = _vault.token1Address();
        address _want = _vault.wantAddress();

        // Exit LP pool
        _exitPool(
            _amount,
            _maxMarketMovementAllowed,
            address(this),
            ExitPoolParams({
                token0: _token0Address,
                token1: _token1Address,
                poolAddress: _want,
                lpTokenAddress: _want
            })
        );

        // Calc token balances
        uint256 _token0Amt = IERC20Upgradeable(_token0Address).balanceOf(
            address(this)
        );
        uint256 _token1Amt = IERC20Upgradeable(_token1Address).balanceOf(
            address(this)
        );

        // Swap token0 for USD
        if (_token0Address != _stablecoin) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _token0Amt,
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

        // Swap token1 for USD
        if (_token1Address != _stablecoin) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _token1Amt,
                    priceToken0: _vault
                        .priceFeeds(_token1Address)
                        .getExchangeRate(),
                    priceToken1: _vault
                        .priceFeeds(_stablecoin)
                        .getExchangeRate(),
                    token0: _token1Address,
                    token1: _stablecoin,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _getSwapPath(_token1Address, _stablecoin),
                    destination: address(this)
                })
            );
        }

        // Calculate USD balance
        usdObtained = IERC20Upgradeable(_stablecoin).balanceOf(address(this));
    }
}
