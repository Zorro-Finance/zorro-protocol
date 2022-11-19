// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../libraries/SafeSwap.sol";

import "../../libraries/PriceFeed.sol";

import "./_VaultActions.sol";

contract VaultActionsZorro is VaultActions {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using SafeMathUpgradeable for uint256;
    using PriceFeed for AggregatorV3Interface;

    /* Structs */

    struct ExchangeUSDForWantParams {
        address stablecoin;
        address tokenZorroAddress;
        AggregatorV3Interface zorroPriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] stablecoinToZorroPath;
    }

    struct ExchangeWantTokenForUSDParams {
        address stablecoin;
        address tokenZorroAddress;
        AggregatorV3Interface zorroPriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] zorroToStablecoinPath;
    }

    /* Functions */

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
        // Safe transfer IN
        IERC20Upgradeable(_params.stablecoin).safeTransferFrom(
            msg.sender,
            address(this),
            _amountUSD
        );

        // Swap USD for token0
        // Single asset. Swap from USD directly to Token0
        _safeSwap(
            SafeSwapParams({
                amountIn: _amountUSD,
                priceToken0: _params.stablecoinPriceFeed.getExchangeRate(),
                priceToken1: _params.zorroPriceFeed.getExchangeRate(),
                token0: _params.stablecoin,
                token1: _params.tokenZorroAddress,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _params.stablecoinToZorroPath,
                destination: address(this)
            })
        );

        // Get new Token0 balance
        uint256 _token0Bal = IERC20Upgradeable(_params.tokenZorroAddress).balanceOf(
            address(this)
        );

        // Calculate resulting want token balance
        uint256 _wantAmt = IERC20Upgradeable(_params.tokenZorroAddress).balanceOf(
            address(this)
        );

        // Transfer back to sender
        // TODO: Should this in fact be msg.sender?
        IERC20Upgradeable(_params.tokenZorroAddress).safeTransfer(
            msg.sender,
            _wantAmt
        );

        return _wantAmt;
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
        IERC20Upgradeable(_params.tokenZorroAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Swap ZOR -> USD
        _safeSwap(
            SafeSwapParams({
                amountIn: _amount,
                priceToken0: _params.zorroPriceFeed.getExchangeRate(),
                priceToken1: _params.stablecoinPriceFeed.getExchangeRate(),
                token0: _params.tokenZorroAddress,
                token1: _params.stablecoin,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _params.zorroToStablecoinPath,
                destination: msg.sender // Is this correct? 
            })
        );

        // Calculate USD balance
        // TODO: Is msg.sender correct here?
        // TODO: In general: Is this the best way? msg.sender can have a 
        // pre-existing balance, making this calculation incorrect
        return IERC20Upgradeable(_params.stablecoin).balanceOf(msg.sender);
    }
}
