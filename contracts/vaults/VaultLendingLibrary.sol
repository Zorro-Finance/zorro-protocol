// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../libraries/SafeSwap.sol";

import "../libraries/PriceFeed.sol";

import "../interfaces/IAlpacaFairLaunch.sol";

import "../interfaces/IAlpacaVault.sol";

import "./VaultLibrary.sol";

library VaultLibraryApeLending {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using SafeMathUpgradeable for uint256;
    using PriceFeed for AggregatorV3Interface;

    struct ExchangeUSDForWantParams {
        address token0Address;
        address stablecoin;
        address tokenZorroAddress;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address uniRouterAddress;
        address[] stablecoinToToken0Path;
        address poolAddress;
    }
    // TODO: Because these xchange... methods are the same for every lending protocol, extract them to a more 
    // TODO generic library (VaultLibraryLending or equiv)
    /// @notice Performs necessary operations to convert USD into Want token
    /// @param _amountUSD The USD quantity to exchange (must already be deposited)
    /// @param _params A ExchangeUSDForWantParams struct
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        ExchangeUSDForWantParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256) {
        // Get balance of deposited BUSD
        uint256 _balBUSD = IERC20Upgradeable(_params.stablecoin).balanceOf(
            address(this)
        );
        // Check that USD was actually deposited
        require(_amountUSD > 0, "dep<=0");
        require(_amountUSD <= _balBUSD, "amt>bal");

        // Use price feed to determine exchange rates
        uint256 _token0ExchangeRate = _params.token0PriceFeed.getExchangeRate();
        uint256 _stablecoinExchangeRate = _params
            .stablecoinPriceFeed
            .getExchangeRate();

        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(_params.stablecoin).decimals();
        _decimals[1] = ERC20Upgradeable(_params.token0Address).decimals();

        // Swap USD for token0
        // Increase allowance
        IERC20Upgradeable(_params.stablecoin).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _amountUSD
        );
        // Single asset. Swap from USD directly to Token0
        if (_params.token0Address != _params.stablecoin) {
            VaultLibrary.safeSwap(
                _params.uniRouterAddress,
                SafeSwapParams({
                    amountIn: _amountUSD,
                    priceToken0: _stablecoinExchangeRate,
                    priceToken1: _token0ExchangeRate,
                    token0: _params.stablecoin,
                    token1: _params.token0Address,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.stablecoinToToken0Path,
                    destination: address(this)
                }),
                _decimals
            );
        }

        // Get new Token0 balance
        uint256 _token0Bal = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );

        // Transfer back to sender
        IERC20Upgradeable(_params.token0Address).safeTransfer(
            msg.sender,
            _token0Bal
        );

        return _token0Bal;
    }

    struct ExchangeWantTokenForUSDParams {
        address token0Address;
        address stablecoin;
        address poolAddress;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] token0ToStablecoinPath;
        address uniRouterAddress;
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be deposited beforehand)
    /// @param _params A ExchangeWantTokenForUSDParams struct
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of USD token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        ExchangeWantTokenForUSDParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256) {
        // Preflight checks
        require(_amount > 0, "negWant");

        // Safely transfer Want/Underlying token from sender
        IERC20Upgradeable(_params.token0Address).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Use price feed to determine exchange rates
        uint256 _token0ExchangeRate = _params.token0PriceFeed.getExchangeRate();
        uint256 _stablecoinExchangeRate = _params
            .stablecoinPriceFeed
            .getExchangeRate();

        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(_params.token0Address).decimals();
        _decimals[1] = ERC20Upgradeable(_params.stablecoin).decimals();

        // Swap Token0 for BUSD
        // Increase allowance
        IERC20Upgradeable(_params.token0Address).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _amount
        );
        // Swap Token0 -> BUSD
        if (_params.token0Address != _params.stablecoin) {
            VaultLibrary.safeSwap(
                _params.uniRouterAddress,
                SafeSwapParams({
                    amountIn: _amount,
                    priceToken0: _token0ExchangeRate,
                    priceToken1: _stablecoinExchangeRate,
                    token0: _params.token0Address,
                    token1: _params.stablecoin,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.token0ToStablecoinPath,
                    destination: msg.sender
                }),
                _decimals
            );
        }

        // Calculate USD balance
        return IERC20Upgradeable(_params.stablecoin).balanceOf(msg.sender);
    }

    struct SwapEarnedToUSDParams {
        address earnedAddress;
        address stablecoin;
        address[] earnedToStablecoinPath;
        address uniRouterAddress;
        uint256 stablecoinExchangeRate;
    }

    /// @notice Swaps Earn token to USD and sends to destination specified
    /// @param _earnedAmount Quantity of Earned tokens
    /// @param _destination Address to send swapped USD to
    /// @param _maxMarketMovementAllowed Slippage factor. 950 = 5%, 990 = 1%, etc.
    /// @param _rates ExchangeRates struct with realtime rates information for swaps
    function swapEarnedToUSD(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed,
        VaultLibrary.ExchangeRates memory _rates,
        SwapEarnedToUSDParams memory _swapEarnedToUSDParams
    ) public {
        // Get exchange rate

        // Get decimal info
        uint8[] memory _decimals0 = new uint8[](2);
        _decimals0[0] = ERC20Upgradeable(_swapEarnedToUSDParams.earnedAddress)
            .decimals();
        _decimals0[1] = ERC20Upgradeable(_swapEarnedToUSDParams.stablecoin)
            .decimals();
        uint8[] memory _decimals1 = new uint8[](2);
        // TODO: decimals1 unused?
        _decimals1[0] = _decimals0[1];
        _decimals1[1] = ERC20Upgradeable(
            _swapEarnedToUSDParams.stablecoin
        ).decimals();

        // Swap BANANA to BUSD
        VaultLibrary.safeSwap(
            _swapEarnedToUSDParams.uniRouterAddress,
            SafeSwapParams({
                amountIn: _earnedAmount,
                priceToken0: _rates.earn,
                priceToken1: _swapEarnedToUSDParams.stablecoinExchangeRate,
                token0: _swapEarnedToUSDParams.earnedAddress,
                token1: _swapEarnedToUSDParams.stablecoin,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _swapEarnedToUSDParams.earnedToStablecoinPath,
                destination: _destination
            }),
            _decimals0
        );
    }
}