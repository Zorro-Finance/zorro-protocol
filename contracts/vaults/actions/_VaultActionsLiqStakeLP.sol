// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "../../interfaces/IAMMRouter02.sol";

import "../../interfaces/Zorro/Vaults/IVaultLiqStakeLP.sol";

import "../../libraries/PriceFeed.sol";

import "./_VaultActions.sol";

abstract contract VaultActionsLiqStakeLP is VaultActions {
    /* Libs */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Structs */

    struct StakeLiqTokenInLPPoolParams {
        address liquidStakeToken;
        address nativeToken;
        AggregatorV3Interface liquidStakeTokenPriceFeed;
        AggregatorV3Interface nativeTokenPriceFeed;
        address[] liquidStakeToNativePath;
    }

    struct UnstakeLiqTokenFromLPPoolParams {
        address liquidStakeToken;
        address nativeToken;
        address lpPoolToken;
        AggregatorV3Interface liquidStakeTokenPriceFeed;
        AggregatorV3Interface nativeTokenPriceFeed;
        address[] nativeToLiquidStakePath;
    }

    /* Functions */

    /// @notice Deposits liquid stake on protocol
    /// @dev Must be implemented by inherited contracts
    function liquidStake(
        uint256 _amount,
        address _token0,
        address _liqStakeToken,
        address _liqStakePool
    ) public virtual;

    /// @notice Withdraws liquid stake on protocol
    /// @dev Must be implemented by inherited contracts
    function liquidUnstake(SafeSwapUni.SafeSwapParams memory _swapParams)
        public
        virtual;

    /// @notice Calculates accumulated unrealized profits on a vault
    /// @param _vault The vault address
    /// @return accumulatedProfit Amount of unrealized profit accumulated on the vault (not accounting for past harvests)
    /// @return harvestableProfit Amount of immediately harvestable profits
    function unrealizedProfits(address _vault)
        public
        view
        override
        returns (uint256 accumulatedProfit, uint256 harvestableProfit) {
            // TODO: Fill
        }

    /// @notice Measures the current (unrealized) position value (measured in Want token) of the provided vault
    /// @param _vault The vault address
    /// @return positionVal Position value, in units of Want token
    function currentWantEquity(address _vault)
        public
        view
        override
        returns (uint256 positionVal) {
            // TODO: Fill
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

    // TODO: Docstrings
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

    /// @notice Swaps and stakes synthetic token in Uni LP Pool
    /// @param _amount Quantity of sETH to swap and stake
    /// @param _params A StakeLiqTokenInLPPoolParams struct describing the stake interactions
    /// @param _maxMarketMovementAllowed Slippage parameter (990 = 1%)
    function stakeInLPPool(
        uint256 _amount,
        StakeLiqTokenInLPPoolParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public {
        // Transfer funds IN
        IERC20Upgradeable(_params.liquidStakeToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

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
            msg.sender
        );
    }
}
