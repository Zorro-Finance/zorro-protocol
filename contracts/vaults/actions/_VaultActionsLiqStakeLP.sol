// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "../../interfaces/Uniswap/IAMMRouter02.sol";

import "../../interfaces/Zorro/Vaults/IVaultLiqStakeLP.sol";

import "../../interfaces/Zorro/Vaults/Actions/IVaultActionsLiqStakeLP.sol";

import "../../libraries/PriceFeed.sol";

import "./_VaultActions.sol";

abstract contract VaultActionsLiqStakeLP is
    IVaultActionsLiqStakeLP,
    VaultActions
{
    /* Libs */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Functions */

    /// @notice Deposits liquid stake on protocol
    /// @dev Must be implemented by inherited contracts
    function _liquidStake(
        uint256 _amount,
        address _token0,
        address _liqStakeToken,
        address _liqStakePool
    ) internal virtual;

    /// @notice Withdraws liquid stake on protocol
    /// @dev Must be implemented by inherited contracts
    function _liquidUnstake(SafeSwapUni.SafeSwapParams memory _swapParams)
        internal
        virtual;

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
        IVaultLiqStakeLP _vault = IVaultLiqStakeLP(_vaultAddr);
        address _token0 = _vault.token0Address(); // Underlying token
        address _liqStakeToken = _vault.liquidStakeToken(); // Amount of synth token (e.g. sETH token)
        address _lpToken = _vault.lpToken(); // Amount of synth token (e.g. sETH token)
        address _earned = _vault.earnedAddress(); // Amount of farm token (e.g. Qi)
        AggregatorV3Interface _token0PriceFeed = _vault.priceFeeds(_token0);
        AggregatorV3Interface _liqStakeTokenPriceFeed = _vault.priceFeeds(
            _liqStakeToken
        );
        AggregatorV3Interface _earnPriceFeed = _vault.priceFeeds(_earned);
        bool _isFarmable = _vault.isLPFarmable();
        address _farm = _vault.farmContract();

        // Get balance of underlying (Token0)
        uint256 _balToken0 = IERC20Upgradeable(_token0).balanceOf(_vaultAddr);

        // Get balance of sETH
        uint256 _balLiqStakeToken = IERC20Upgradeable(_liqStakeToken).balanceOf(
            _vaultAddr
        );

        // Express balance of sETH in ETH
        uint256 _balLiqStakeTokenToken0 = (_balLiqStakeToken *
            _liqStakeTokenPriceFeed.getExchangeRate()) /
            _token0PriceFeed.getExchangeRate();

        // Get balance of sETH-ETH LP token
        uint256 _balLPToken = IERC20Upgradeable(_lpToken).balanceOf(_vaultAddr);

        // Express balance in ETH
        uint256 _totalSupplyLP = IERC20Upgradeable(_lpToken).totalSupply();
        uint256 _balToken0LP = IERC20Upgradeable(_token0).balanceOf(_lpToken);
        uint256 _balLPTokenToken0 = _balLPToken * _balToken0LP / _totalSupplyLP;

        // Farm activity (if applicable)
        uint256 _stakedLPToken0;
        uint256 _pendingEarnToken0;

        if (_isFarmable) {
            // Get balance of sETH-ETH LP token staked on Masterchef (if isFarmable)
            (uint256 _amtLPStaked, ) = IAMMFarm(_farm).user(pid, _vaultAddr);

            // Express in Token0 units
            _stakedLPToken0 = _amtLPStaked * _balToken0LP / _totalSupplyLP;

            // Get pending Earn
            uint256 _pendingEarn = IAMMFarm(_farm).pendingCake(pid, _vaultAddr);

            // Express in Token0 units
            _pendingEarnToken0 = _pendingEarn * _earnPriceFeed.getExchangeRate() / _token0PriceFeed.getExchangeRate();
        }

        // Sum up all equities
        positionVal = _balToken0 + _balLiqStakeTokenToken0 + _balLPTokenToken0 + _stakedLPToken0 + _pendingEarnToken0;
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be approved beforehand)
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return returnedUSD Amount of USD token obtained
    function _exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) internal override returns (uint256 returnedUSD) {
        // Prep
        IVault _vault = IVault(_msgSender());
        address _token0Address = _vault.token0Address();
        address _stablecoin = _vault.defaultStablecoin();

        // Calc ETH bal
        uint256 _token0Bal = IERC20Upgradeable(_token0Address).balanceOf(
            address(this)
        );

        // Swap ETH to USD
        _safeSwap(
            SafeSwapUni.SafeSwapParams({
                amountIn: _token0Bal,
                priceToken0: _vault
                    .priceFeeds(_token0Address)
                    .getExchangeRate(),
                priceToken1: _vault.priceFeeds(_stablecoin).getExchangeRate(),
                token0: _token0Address,
                token1: _stablecoin,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _getSwapPath(_token0Address, _stablecoin),
                destination: address(this)
            })
        );

        // Return USD amount
        returnedUSD = IERC20Upgradeable(_stablecoin).balanceOf(address(this));
    }

    function _exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) internal override returns (uint256 returnedWant) {
        // Prep
        IVault _vault = IVault(_msgSender());
        address _stablecoin = _vault.defaultStablecoin();
        address _token0Address = _vault.token0Address();

        // Swap USD for ETH
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

        // Get ETH balance
        returnedWant = IERC20Upgradeable(_token0Address).balanceOf(
            address(this)
        );
    }

    /// @notice Liquid stakes ETH and adds liquidity to sETH-ETH pool, sending back LP token to sender
    /// @param _amount Amount of ETH to liquid stake
    /// @param _nativeToken ETH address
    /// @param _liqStakeToken sETH address
    /// @param _liqStakePool pool address for liquid staking
    /// @param _maxMarketMovementAllowed Slippage parameter (990 = 1%)
    function liquidStakeAndAddLiq(
        uint256 _amount,
        address _nativeToken,
        address _liqStakeToken,
        address _liqStakePool,
        uint256 _maxMarketMovementAllowed
    ) public {
        // Transfer native token IN
        IERC20Upgradeable(_nativeToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Liquid stake
        _liquidStake(_amount, _nativeToken, _liqStakeToken, _liqStakePool);

        // Calc balance of sETH on this contract
        uint256 _synthBal = IERC20Upgradeable(_liqStakeToken).balanceOf(
            address(this)
        );

        // Prep vars for adding liquidity
        IVaultLiqStakeLP _vault = IVaultLiqStakeLP(msg.sender);
        AggregatorV3Interface _liqStakeTokenPriceFeed = _vault.priceFeeds(
            _liqStakeToken
        );
        AggregatorV3Interface _nativeTokenPriceFeed = _vault.priceFeeds(
            _nativeToken
        );
        address[] memory _liquidStakeToNativePath = _getSwapPath(
            _liqStakeToken,
            _nativeToken
        );

        // Add liquidity
        _stakeInLPPool(
            _synthBal,
            StakeLiqTokenInLPPoolParams({
                liquidStakeToken: _liqStakeToken,
                nativeToken: _nativeToken,
                liquidStakeTokenPriceFeed: _liqStakeTokenPriceFeed,
                nativeTokenPriceFeed: _nativeTokenPriceFeed,
                liquidStakeToNativePath: _liquidStakeToNativePath
            }),
            _maxMarketMovementAllowed,
            msg.sender
        );
    }

    /// @notice Removes liquidity from sETH-ETH pool, and exchanges sETH for ETH, back to sender
    /// @param _amount The amount of sETH-ETH LP token to remove liquidity with
    /// @param _nativeToken Address of ETH
    /// @param _liquidStakeToken Address of sETH
    /// @param _lpToken Address of sETH-ETH LP Pool
    /// @param _maxMarketMovementAllowed Slippage factor (990 = 1%)
    function removeLiqAndliquidUnstake(
        uint256 _amount,
        address _nativeToken,
        address _liquidStakeToken,
        address _lpToken,
        uint256 _maxMarketMovementAllowed
    ) public {
        // Transfer LP token IN
        IERC20Upgradeable(_lpToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Exit LP pool and get back sETH, WETH
        _exitPool(
            _amount,
            _maxMarketMovementAllowed,
            address(this),
            ExitPoolParams({
                token0: _nativeToken,
                token1: _liquidStakeToken,
                poolAddress: _lpToken,
                lpTokenAddress: _lpToken
            })
        );

        // Calc sETH balance
        uint256 _synthTokenBal = IERC20Upgradeable(_liquidStakeToken).balanceOf(
            address(this)
        );

        // Prep swap variables
        IVaultLiqStakeLP _vault = IVaultLiqStakeLP(msg.sender);
        AggregatorV3Interface _nativeTokenPriceFeed = _vault.priceFeeds(
            _nativeToken
        );
        AggregatorV3Interface _liqStakeTokenPriceFeed = _vault.priceFeeds(
            _liquidStakeToken
        );

        // Unstake sETH to get ETH
        _liquidUnstake(
            SafeSwapUni.SafeSwapParams({
                amountIn: _synthTokenBal,
                priceToken0: _nativeTokenPriceFeed.getExchangeRate(),
                priceToken1: _liqStakeTokenPriceFeed.getExchangeRate(),
                token0: _nativeToken,
                token1: _liquidStakeToken,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _getSwapPath(_liquidStakeToken, _nativeToken),
                destination: msg.sender
            })
        );
    }

    /// @notice Swaps and stakes synthetic token in Uni LP Pool
    /// @param _amount Quantity of sETH to swap and stake
    /// @param _params A StakeLiqTokenInLPPoolParams struct describing the stake interactions
    /// @param _maxMarketMovementAllowed Slippage parameter (990 = 1%)
    /// @param _destination Where to send LP tokens
    function _stakeInLPPool(
        uint256 _amount,
        StakeLiqTokenInLPPoolParams memory _params,
        uint256 _maxMarketMovementAllowed,
        address _destination
    ) internal {
        // Swap half of sETH to ETH
        _safeSwap(
            SafeSwapUni.SafeSwapParams({
                amountIn: _amount / 2,
                priceToken0: _params
                    .liquidStakeTokenPriceFeed
                    .getExchangeRate(),
                priceToken1: _params.nativeTokenPriceFeed.getExchangeRate(),
                token0: _params.liquidStakeToken,
                token1: _params.nativeToken,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _params.liquidStakeToNativePath,
                destination: address(this)
            })
        );

        // Calc balances
        uint256 _synthTokenBal = IERC20Upgradeable(_params.liquidStakeToken)
            .balanceOf(address(this));
        uint256 _token0Bal = IERC20Upgradeable(_params.nativeToken).balanceOf(
            address(this)
        );

        // Add liquidity to sETH-ETH pool and send back to sender
        _joinPool(
            _params.liquidStakeToken,
            _params.nativeToken,
            _synthTokenBal,
            _token0Bal,
            _maxMarketMovementAllowed,
            _destination
        );
    }
}
