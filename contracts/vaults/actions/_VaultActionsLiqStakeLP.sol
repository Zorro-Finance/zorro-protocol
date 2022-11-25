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

    struct ExchangeUSDForWantParams {
        address token0Address;
        address stablecoin;
        address liquidStakeToken;
        address liquidStakePool;
        address poolAddress;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface liquidStakeTokenPriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] stablecoinToToken0Path;
        address[] liquidStakeToToken0Path;
    }

    struct ExchangeWantTokenForUSDParams {
        address token0Address;
        address stablecoin;
        address poolAddress;
        address liquidStakeToken;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface liquidStakeTokenPriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] liquidStakeToToken0Path;
        address[] token0ToStablecoinPath;
    }

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
    function _liquidStake(
        uint256 _amount,
        address _token0,
        address _liqStakeToken,
        address _liqStakePool
    ) internal virtual;

    /// @notice Withdraws liquid stake on protocol
    /// @dev Must be implemented by inherited contracts
    function _liquidUnstake(SafeSwapUni.SafeSwapParams memory _swapParams) internal virtual;

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be approved beforehand)
    /// @param _params ExchangeWantTokenForUSDParams struct
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return returnedUSD Amount of USD token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        ExchangeWantTokenForUSDParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256 returnedUSD) {
        // Transfer amount IN
        IERC20Upgradeable(_params.liquidStakeToken).safeTransferFrom(
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
                token0: _params.liquidStakeToken,
                token1: _params.token0Address,
                poolAddress: _params.poolAddress,
                lpTokenAddress: _params.poolAddress
            })
        );

        // Calc sETH balance
        uint256 _synthTokenBal = IERC20Upgradeable(_params.liquidStakeToken)
            .balanceOf(address(this));

        // Unstake sETH to get ETH
        _liquidUnstake(
            SafeSwapUni.SafeSwapParams({
                amountIn: _synthTokenBal,
                priceToken0: _params
                    .liquidStakeTokenPriceFeed
                    .getExchangeRate(),
                priceToken1: _params.token0PriceFeed.getExchangeRate(),
                token0: _params.liquidStakeToken,
                token1: _params.token0Address,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _params.liquidStakeToToken0Path,
                destination: address(this)
            })
        );

        // Calc ETH bal
        uint256 _token0Bal = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );

        // Swap ETH to USD
        _safeSwap(
            SafeSwapUni.SafeSwapParams({
                amountIn: _token0Bal,
                priceToken0: _params.token0PriceFeed.getExchangeRate(),
                priceToken1: _params.stablecoinPriceFeed.getExchangeRate(),
                token0: _params.token0Address,
                token1: _params.stablecoin,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _params.token0ToStablecoinPath,
                destination: address(this)
            })
        );

        // Return USD amount
        returnedUSD = IERC20Upgradeable(_params.stablecoin).balanceOf(
            address(this)
        );

        // Transfer USD back to sender
        IERC20Upgradeable(_params.stablecoin).safeTransfer(
            msg.sender,
            returnedUSD
        );
    }

    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        ExchangeUSDForWantParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256 returnedWant) {
        // Transfer amount IN
        IERC20Upgradeable(_params.stablecoin).safeTransferFrom(
            msg.sender,
            address(this),
            _amountUSD
        );

        // Swap USD for ETH
        _safeSwap(
            SafeSwapUni.SafeSwapParams({
                amountIn: _amountUSD,
                priceToken0: _params.stablecoinPriceFeed.getExchangeRate(),
                priceToken1: _params.token0PriceFeed.getExchangeRate(),
                token0: _params.stablecoin,
                token1: _params.token0Address,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _params.stablecoinToToken0Path,
                destination: address(this)
            })
        );

        // Get ETH balance
        uint256 _token0Bal = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );

        // Stake ETH (liquid staking)
        _liquidStake(
            _token0Bal,
            _params.token0Address,
            _params.liquidStakeToken,
            _params.liquidStakePool
        );

        // Get bal of sETH

        // Return bal of want tokens (same as Token0)
        returnedWant = IERC20Upgradeable(_params.liquidStakeToken).balanceOf(
            address(this)
        );

        // Transfer back to sender
        IERC20Upgradeable(_params.liquidStakeToken).safeTransfer(
            msg.sender,
            returnedWant
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
                priceToken0: _params.liquidStakeTokenPriceFeed.getExchangeRate(),
                priceToken1: _params.nativeTokenPriceFeed.getExchangeRate(),
                token0: _params.liquidStakeToken,
                token1: _params.nativeToken,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _params.liquidStakeToNativePath,
                destination: address(this)
            })
        );

        // Calc balances
        uint256 _synthTokenBal = IERC20Upgradeable(_params.liquidStakeToken).balanceOf(
            address(this)
        );
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

    /// @notice Takes sETH-ETH LP pool token and converts to sETH
    /// @param _amount Quantity of LP token to convert to sETH
    /// @param _params A UnstakeLiqTokenFromLPPoolParams struct describing the unstake interaction
    /// @param _maxMarketMovementAllowed Slippage parameter (990 = 1%)
    function unStakeFromLPPool(
        uint256 _amount,
        UnstakeLiqTokenFromLPPoolParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public {
        // Transfer funds IN
        IERC20Upgradeable(_params.lpPoolToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Exit pool
        _exitPool(
            _amount,
            _maxMarketMovementAllowed,
            address(this),
            ExitPoolParams({
                token0: _params.liquidStakeToken,
                token1: _params.nativeToken,
                poolAddress: _params.lpPoolToken,
                lpTokenAddress: _params.lpPoolToken
            })
        );

        // Calc balance of ETH
        uint256 _token0Bal = IERC20Upgradeable(_params.nativeToken).balanceOf(
            address(this)
        );

        // Swap ETH to sETH
        _safeSwap(
            SafeSwapUni.SafeSwapParams({
                amountIn: _token0Bal,
                priceToken0: _params.liquidStakeTokenPriceFeed.getExchangeRate(),
                priceToken1: _params.nativeTokenPriceFeed.getExchangeRate(),
                token0: _params.nativeToken,
                token1: _params.liquidStakeToken,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _params.nativeToLiquidStakePath,
                destination: address(this)
            })
        );

        // Calc balance of sETH
        uint256 _synthBal = IERC20Upgradeable(_params.liquidStakeToken).balanceOf(
            address(this)
        );

        // Transfer back to sender
        IERC20Upgradeable(_params.liquidStakeToken).safeTransfer(msg.sender, _synthBal);
    }

    // TODO: Docstrings
    function _convertRemainingEarnedToWant(
        uint256 _remainingEarnAmt,
        uint256 _maxMarketMovementAllowed,
        address _destination
    ) internal override returns (uint256 wantObtained) {
        // Prep
        IVaultLiqStakeLP _vault = IVaultLiqStakeLP(msg.sender);

        address _earnedAddress = _vault.earnedAddress();
        address _token0Address = _vault.token0Address();
        address _liquidStakeToken = _vault.liquidStakeToken();
        address _liquidStakingPool = _vault.liquidStakingPool();
        address _wantAddress = _vault.wantAddress();
        AggregatorV3Interface _token0PriceFeed = _vault.token0PriceFeed();
        AggregatorV3Interface _earnTokenPriceFeed = _vault.earnTokenPriceFeed();

        // Swap Earned token to token0 if token0 is not the Earned token
        if (_earnedAddress != _token0Address) {
            // Swap earned to token0
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _remainingEarnAmt,
                    priceToken0: _earnTokenPriceFeed.getExchangeRate(),
                    priceToken1: _token0PriceFeed.getExchangeRate(),
                    token0: _earnedAddress,
                    token1: _token0Address,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _vault.earnedToToken0Path(),
                    destination: address(this)
                })
            );
        }

        // Get balance of Token 0 (ETH)
        uint256 _token0Bal = IERC20Upgradeable(_token0Address).balanceOf(
            address(this)
        );

        // Provided that token0 is > 0, re-deposit
        if (_token0Bal > 0) {
            _liquidStake(
                _token0Bal,
                _token0Address,
                _liquidStakeToken,
                _liquidStakingPool
            );
        }

        // Calc want balance
        wantObtained = IERC20Upgradeable(_liquidStakeToken).balanceOf(address(this));

        // Transfer want token to destination
        IERC20Upgradeable(_liquidStakeToken).safeTransfer(_destination, wantObtained);
    }
}
