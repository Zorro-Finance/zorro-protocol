// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../libraries/SafeSwap.sol";

import "../../libraries/PriceFeed.sol";

import "../../interfaces/Alpaca/IAlpacaFairLaunch.sol";

import "../../interfaces/Alpaca/IAlpacaVault.sol";

import "../../interfaces/IAMMRouter02.sol";

import "./_VaultActions.sol";

contract VaultActionsStandardAMM is VaultActions {
    /* Libraries */

    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /* Structs */

    // TODO: Rather than passing around these vars and structs, consider taking
    // vars that are constant across all vaults (e.g. the ZOR token) and storing
    // them on contract. 

    struct ExchUSDToWantParams {
        address stablecoin;
        address token0Address;
        address token1Address;
        address wantAddress;
        AggregatorV3Interface stablecoinPriceFeed;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface token1PriceFeed;
        address[] stablecoinToToken0Path;
        address[] stablecoinToToken1Path;
    }

    struct ExchWantToUSDParams {
        address stablecoin;
        address token0Address;
        address token1Address;
        address wantAddress;
        address poolAddress;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface token1PriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] token0ToStablecoinPath;
        address[] token1ToStablecoinPath;
    }

    /* Functions */

    /// @notice Performs necessary operations to convert USD into Want token and transfer back to sender
    /// @dev NOTE: Requires caller to approve spending beforehand
    /// @param _amountUSD The amount of USD to exchange for Want token (must already be deposited on this contract)
    /// @param _params A ExchUSDToWantParams struct
    /// @param _maxMarketMovementAllowed Slippage (990 = 1% etc.)
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        ExchUSDToWantParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256) {
        // Safe transfer IN
        IERC20Upgradeable(_params.stablecoin).safeTransferFrom(
            msg.sender,
            address(this),
            _amountUSD
        );

        // Swap 1/2 USD for token0
        if (_params.token0Address != _params.stablecoin) {
            _safeSwap(
                SafeSwapParams({
                    amountIn: _amountUSD.div(2),
                    priceToken0: _params.stablecoinPriceFeed.getExchangeRate(),
                    priceToken1: _params.token0PriceFeed.getExchangeRate(),
                    token0: _params.stablecoin,
                    token1: _params.token0Address,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.stablecoinToToken0Path,
                    destination: address(this)
                })
            );
        }

        // Swap 1/2 USD for token1
        if (_params.token1Address != _params.stablecoin) {
            _safeSwap(
                SafeSwapParams({
                    amountIn: _amountUSD.div(2),
                    priceToken0: _params.stablecoinPriceFeed.getExchangeRate(),
                    priceToken1: _params.token1PriceFeed.getExchangeRate(),
                    token0: _params.stablecoin,
                    token1: _params.token1Address,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.stablecoinToToken1Path,
                    destination: address(this)
                })
            );
        }

        // Deposit token0, token1 into LP pool to get Want token (i.e. LP token)
        uint256 _token0Amt = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );
        uint256 _token1Amt = IERC20Upgradeable(_params.token1Address).balanceOf(
            address(this)
        );

        // Add liquidity
        _joinPool(
            _params.token0Address,
            _params.token1Address,
            _token0Amt,
            _token1Amt,
            _maxMarketMovementAllowed,
            msg.sender
        );

        // Calculate resulting want token balance
        // TODO: Should this be msg.sender? Or the sender's sender?
        return IERC20Upgradeable(_params.wantAddress).balanceOf(msg.sender);
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal, transfers back to sender
    /// @param _amount The Want token quantity to exchange
    /// @param _params ExchWantToUSDParams struct
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of USD token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        ExchWantToUSDParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256) {
        // Preflight checks
        require(_amount > 0, "negWant");

        // Safely transfer Want token from sender
        IERC20Upgradeable(_params.wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Exit LP pool
        _exitPool(
            _amount,
            _maxMarketMovementAllowed,
            address(this),
            ExitPoolParams({
                token0: _params.token0Address,
                token1: _params.token1Address,
                poolAddress: _params.poolAddress,
                wantAddress: _params.wantAddress
            })
        );

        // Swap tokens back to USD
        uint256 _token0Amt = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );
        uint256 _token1Amt = IERC20Upgradeable(_params.token1Address).balanceOf(
            address(this)
        );

        // Swap token0 for USD
        if (_params.token0Address != _params.stablecoin) {
            _safeSwap(
                SafeSwapParams({
                    amountIn: _token0Amt,
                    priceToken0: _params.token0PriceFeed.getExchangeRate(),
                    priceToken1: _params.stablecoinPriceFeed.getExchangeRate(),
                    token0: _params.token0Address,
                    token1: _params.stablecoin,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.token0ToStablecoinPath,
                    destination: address(this)
                })
            );
        }

        // Swap token1 for USD
        if (_params.token1Address != _params.stablecoin) {
            _safeSwap(
                SafeSwapParams({
                    amountIn: _token1Amt,
                    priceToken0: _params.token1PriceFeed.getExchangeRate(),
                    priceToken1: _params.stablecoinPriceFeed.getExchangeRate(),
                    token0: _params.token1Address,
                    token1: _params.stablecoin,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.token1ToStablecoinPath,
                    destination: address(this)
                })
            );
        }

        // Calculate USD balance // TODO: Is this correct? or should it be the caller of msg.sender?
        return IERC20Upgradeable(_params.stablecoin).balanceOf(msg.sender);
    }

    /// @notice Buys back earn token, adds liquidity, and burns the LP token
    // TODO docstrings
    function buybackBurnLP(
        uint256 _amount, 
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates,
        BuybackBurnLPParams memory _params
    )
        public
    {
        // Transfer tokens IN
        IERC20Upgradeable(_params.earnedAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Swap to ZOR Token
        if (_params.earnedAddress != _params.ZORROAddress) {
            _safeSwap(
                SafeSwapParams({
                    amountIn: _amount.div(2),
                    priceToken0: _rates.earn,
                    priceToken1: _rates.ZOR,
                    token0: _params.earnedAddress,
                    token1: _params.ZORROAddress,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.earnedToZORROPath,
                    destination: address(this)
                })
            );
        }
        // Swap to Other token
        if (_params.earnedAddress != _params.zorroLPPoolOtherToken) {
            _safeSwap(
                SafeSwapParams({
                    amountIn: _amount.div(2),
                    priceToken0: _rates.earn,
                    priceToken1: _rates.lpPoolOtherToken,
                    token0: _params.earnedAddress,
                    token1: _params.zorroLPPoolOtherToken,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.earnedToZORLPPoolOtherTokenPath,
                    destination: address(this)
                })
            );
        }

        // Calc balances
        uint256 _amtZorro = IERC20Upgradeable(_params.ZORROAddress).balanceOf(
            address(this)
        );
        uint256 _amtOtherToken = IERC20Upgradeable(_params.zorroLPPoolOtherToken)
            .balanceOf(address(this));

        // Add liquidity and burn
        _joinPool(
            _params.ZORROAddress,
            _params.zorroLPPoolOtherToken,
            _amtZorro,
            _amtOtherToken,
            _maxMarketMovementAllowed,
            burnAddress
        );
    }
}
