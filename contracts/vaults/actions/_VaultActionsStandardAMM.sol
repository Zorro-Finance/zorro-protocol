// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/Alpaca/IAlpacaFairLaunch.sol";

import "../../interfaces/Alpaca/IAlpacaVault.sol";

import "../../interfaces/Zorro/Vaults/IVaultStandardAMM.sol";

import "./_VaultActions.sol";

contract VaultActionsStandardAMM is VaultActions {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /* Structs */

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
    /// @return wantObtained Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        ExchUSDToWantParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256 wantObtained) {
        // Safe transfer IN
        IERC20Upgradeable(_params.stablecoin).safeTransferFrom(
            msg.sender,
            address(this),
            _amountUSD
        );

        // Swap 1/2 USD for token0
        if (_params.token0Address != _params.stablecoin) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _amountUSD / 2,
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
                SafeSwapUni.SafeSwapParams({
                    amountIn: _amountUSD / 2,
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
        wantObtained = IERC20Upgradeable(_params.wantAddress).balanceOf(
            msg.sender
        );

        // Transfer back to sender
        IERC20Upgradeable(_params.wantAddress).safeTransfer(
            msg.sender,
            wantObtained
        );
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal, transfers back to sender
    /// @param _amount The Want token quantity to exchange
    /// @param _params ExchWantToUSDParams struct
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return usdObtained Amount of USD token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        ExchWantToUSDParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256 usdObtained) {
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
                lpTokenAddress: _params.wantAddress
            })
        );

        // Calc token balances
        uint256 _token0Amt = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );
        uint256 _token1Amt = IERC20Upgradeable(_params.token1Address).balanceOf(
            address(this)
        );

        // Swap token0 for USD
        if (_params.token0Address != _params.stablecoin) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
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
                SafeSwapUni.SafeSwapParams({
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

        // Calculate USD balance
        usdObtained = IERC20Upgradeable(_params.stablecoin).balanceOf(
            address(this)
        );

        // Transfer back to sender
        IERC20Upgradeable(_params.stablecoin).safeTransfer(
            msg.sender,
            usdObtained
        );
    }

    // TODO: Docstrings 
    function _convertRemainingEarnedToWant(
        uint256 _remainingEarnAmt,
        uint256 _maxMarketMovementAllowed,
        address _destination
    ) internal override returns (uint256 wantObtained) {
        // Prep
        IVault _vault = IVaultStandardAMM(msg.sender);

        address _earnedAddress = _vault.earnedAddress();
        address _token0Address = _vault.token0Address();
        address _token1Address = _vault.token1Address();
        address _wantAddress = _vault.wantAddress();
        AggregatorV3Interface _token0PriceFeed = _vault.token0PriceFeed();
        AggregatorV3Interface _token1PriceFeed = _vault.token1PriceFeed();
        AggregatorV3Interface _earnTokenPriceFeed = _vault.earnTokenPriceFeed();

        // Swap Earned token to token0 if token0 is not the Earned token
        if (_earnedAddress != _token0Address) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _remainingEarnAmt / 2,
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

        // Swap Earned token to token1 if token0 is not the Earned token
        if (_earnedAddress != _token1Address) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _remainingEarnAmt / 2,
                    priceToken0: _earnTokenPriceFeed.getExchangeRate(),
                    priceToken1: _token1PriceFeed.getExchangeRate(),
                    token0: _earnedAddress,
                    token1: _token1Address,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _vault.earnedToToken1Path(),
                    destination: address(this)
                })
            );
        }

        // Get values of tokens 0 and 1
        uint256 token0Amt = IERC20Upgradeable(_token0Address).balanceOf(
            address(this)
        );
        uint256 token1Amt = IERC20Upgradeable(_token1Address).balanceOf(
            address(this)
        );

        // Provided that token0 and token1 are both > 0, add liquidity
        if (token0Amt > 0 && token1Amt > 0) {
            // Add liquidity
            _joinPool(
                _token0Address,
                _token1Address,
                token0Amt,
                token1Amt,
                _maxMarketMovementAllowed,
                address(this)
            );
        }

        // Calc want balance
        wantObtained = IERC20Upgradeable(_wantAddress).balanceOf(address(this));

        // Transfer want token to destination
        IERC20Upgradeable(_wantAddress).safeTransfer(_destination, wantObtained);
    }
}
