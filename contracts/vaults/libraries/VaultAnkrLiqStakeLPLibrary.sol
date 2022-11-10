// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "../../interfaces/Ankr/IBinancePool_R1.sol";

import "../../interfaces/IWETH.sol";

import "../../libraries/SafeSwap.sol";

import "./VaultLibrary.sol";

import "./VaultLiqStakeLPLibrary.sol";

/// @title VaultAnkrLiqStakeLPLibrary for core functions of VaultAnkrLiqStakeLP vaults
library VaultAnkrLiqStakeLPLibrary {
    /* Libs */
    using PriceFeed for AggregatorV3Interface;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    /* Functions */

    /// @notice Deposits liquid stake on Benqi protocol
    /// @param _amount The amount of AVAX to liquid stake
    /// @param _token0 The base (underlying) token to supply
    /// @param _liqStakeToken The liquid staking synthetic token returned after staking the underlying
    /// @param _liqStakePool The liquid staking pool address
    function liquidStake(
        uint256 _amount,
        address _token0,
        address _liqStakeToken,
        address _liqStakePool
    ) public {
        // Preflight checks
        require(_amount >= 0.5 ether, "minLiqStake");

        // Unwrap BNB
        IWETH(_token0).withdraw(_amount);

        // Get native BNB balance
        uint256 _bal = address(this).balance;

        // Require balance to be > amount
        require(_bal > _amount, "insufficientLiqStakeBal");

        // Get relayer fee
        uint256 _relayerFee = IBinancePool_R1(_liqStakeToken).getRelayerFee();

        // Call deposit func
        IBinancePool_R1(_liqStakePool).stakeAndClaimCerts{
            value: _amount.add(_relayerFee)
        }();
    }

    /// @notice Withdraws liquid stake on Benqi protocol
    /// @param _uniRouter The uniswap compatible router contract
    /// @param _swapParams The SafeSwapParams object with swap information
    function liquidUnstake(
        address _uniRouter,
        SafeSwapParams memory _swapParams
    ) public {
        // Exchange sAVAX for WAVAX

        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(_swapParams.token0).decimals();
        _decimals[1] = ERC20Upgradeable(_swapParams.token1).decimals();

        // Swap sAvax to wAVAX
        VaultLibrary.safeSwap(_uniRouter, _swapParams, _decimals);
    }

    struct ExchangeUSDForWantParams {
        address token0Address;
        address stablecoin;
        address liquidStakeToken;
        address liquidStakePool;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface liquidStakeTokenPriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address uniRouterAddress;
        address[] stablecoinToToken0Path;
        address[] liquidStakeToToken0Path;
        address poolAddress;
        address wantAddress;
    }

    /// @notice Performs necessary operations to convert USD into Want token
    /// @param _amountUSD The USD quantity to exchange (must already be deposited)
    /// @param _params A ExchangeUSDForWantParams struct
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return returnedWant Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        ExchangeUSDForWantParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256 returnedWant) {
        // Swap USD for Avax
        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(_params.stablecoin).decimals();
        _decimals[1] = ERC20Upgradeable(_params.token0Address).decimals();

        // Swap usd to token0 if token0 is not usd
        if (_params.stablecoin != _params.token0Address) {
            VaultLibrary.safeSwap(
                _params.uniRouterAddress,
                SafeSwapParams({
                    amountIn: _amountUSD,
                    priceToken0: _params.stablecoinPriceFeed.getExchangeRate(),
                    priceToken1: _params.token0PriceFeed.getExchangeRate(),
                    token0: _params.stablecoin,
                    token1: _params.token0Address,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.stablecoinToToken0Path,
                    destination: address(this)
                }),
                _decimals
            );
        }

        // Get Avax balance
        uint256 _token0Bal = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );

        // Stake AVAX (liquid staking)
        liquidStake(
            _token0Bal,
            _params.token0Address,
            _params.liquidStakeToken,
            _params.liquidStakePool
        );

        // Get bal of sAVAX
        uint256 _synthTokenBal = IERC20Upgradeable(_params.liquidStakeToken)
            .balanceOf(address(this));

        // Add liquidity to sAVAX-AVAX pool
        VaultLiqStakeLPLibrary.addLiquidity(
            _synthTokenBal,
            VaultLiqStakeLPLibrary.AddLiquidityParams({
                uniRouterAddress: _params.uniRouterAddress,
                token0Address: _params.token0Address,
                liquidStakeToken: _params.liquidStakeToken,
                liquidStakeToToken0Path: _params.liquidStakeToToken0Path,
                token0PriceFeed: _params.token0PriceFeed,
                liquidStakeTokenPriceFeed: _params.liquidStakeTokenPriceFeed,
                maxMarketMovementAllowed: _maxMarketMovementAllowed
            })
        );

        // Return bal of want tokens (same as Token0)
        return IERC20Upgradeable(_params.wantAddress).balanceOf(address(this));
    }

    struct ExchangeWantTokenForUSDParams {
        address token0Address;
        address stablecoin;
        address wantAddress;
        address poolAddress;
        address liquidStakeToken;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface liquidStakeTokenPriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] liquidStakeToToken0Path;
        address[] token0ToStablecoinPath;
        address uniRouterAddress;
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be deposited beforehand)
    /// @param _params ExchangeWantTokenForUSDParams struct
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return returnedUSD Amount of USD token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        ExchangeWantTokenForUSDParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256 returnedUSD) {
        // Exit LP pool and get back sAvax
        VaultLiqStakeLPLibrary.removeLiquidity(
            _amount,
            VaultLiqStakeLPLibrary.RemoveLiquidityParams({
                uniRouterAddress: _params.uniRouterAddress,
                poolAddress: _params.poolAddress,
                token0Address: _params.token0Address,
                liquidStakeToken: _params.liquidStakeToken,
                maxMarketMovementAllowed: _maxMarketMovementAllowed
            })
        );

        // Swap sAvax for Avax (token0)
        uint256 _synthTokenBal = IERC20Upgradeable(_params.liquidStakeToken)
            .balanceOf(address(this));
        liquidUnstake(
            _params.uniRouterAddress,
            SafeSwapParams({
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

        // Swap AVAX to USD
        // Calc Avax bal
        uint256 _token0Bal = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );
        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(_params.token0Address).decimals();
        _decimals[1] = ERC20Upgradeable(_params.stablecoin).decimals();
        // Swap
        VaultLibrary.safeSwap(
            _params.uniRouterAddress,
            SafeSwapParams({
                amountIn: _token0Bal,
                priceToken0: _params.token0PriceFeed.getExchangeRate(),
                priceToken1: _params.stablecoinPriceFeed.getExchangeRate(),
                token0: _params.token0Address,
                token1: _params.stablecoin,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _params.token0ToStablecoinPath,
                destination: address(this)
            }),
            _decimals
        );

        // Return USD amount
        returnedUSD = IERC20Upgradeable(_params.stablecoin).balanceOf(
            address(this)
        );
        IERC20Upgradeable(_params.stablecoin).safeTransfer(
            msg.sender,
            returnedUSD
        );
    }
}
