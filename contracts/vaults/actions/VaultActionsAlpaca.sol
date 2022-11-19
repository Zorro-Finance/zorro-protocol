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

contract VaultActionsAlpaca is VaultActions {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using SafeMathUpgradeable for uint256;
    using PriceFeed for AggregatorV3Interface;

    /* Structs */

    struct ExchangeUSDForWantParams {
        address token0Address;
        address stablecoin;
        address tokenZorroAddress;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address uniRouterAddress;
        address[] stablecoinToToken0Path;
        address poolAddress;
        address wantAddress;
    }

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
        // Single asset. Swap from USD directly to Token0
        if (_params.token0Address != _params.stablecoin) {
            _safeSwap(
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

        // Increase allowance
        IERC20Upgradeable(_params.token0Address).safeIncreaseAllowance(
            _params.poolAddress,
            _token0Bal
        );

        // Deposit token to get Want token
        IAlpacaVault(_params.poolAddress).deposit(_token0Bal);

        // Calculate resulting want token balance
        uint256 _wantAmt = IERC20Upgradeable(_params.wantAddress).balanceOf(
            address(this)
        );

        // Transfer back to sender
        IERC20Upgradeable(_params.wantAddress).safeTransfer(
            msg.sender,
            _wantAmt
        );

        return _wantAmt;
    }

    struct ExchangeWantTokenForUSDParams {
        address token0Address;
        address stablecoin;
        address wantAddress;
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

        // Safely transfer Want token from sender
        IERC20Upgradeable(_params.wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Approve
        IERC20Upgradeable(_params.wantAddress).safeIncreaseAllowance(
            _params.poolAddress,
            _amount
        );

        // Withdraw Want token to get Token0
        IAlpacaVault(_params.poolAddress).withdraw(_amount);

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
        // Get Token0 balance
        uint256 _token0Bal = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );
        // Increase allowance
        IERC20Upgradeable(_params.token0Address).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _token0Bal
        );
        // Swap Token0 -> BUSD
        if (_params.token0Address != _params.stablecoin) {
            VaultLibrary.safeSwap(
                _params.uniRouterAddress,
                SafeSwapParams({
                    amountIn: _token0Bal,
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
}