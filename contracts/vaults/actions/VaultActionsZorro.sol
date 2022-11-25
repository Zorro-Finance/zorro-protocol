// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../libraries/PriceFeed.sol";

import "./_VaultActions.sol";

contract VaultActionsZorro is VaultActions {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
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
    /// @return wantObtained Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        ExchangeUSDForWantParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256 wantObtained) {
        // Safe transfer IN
        IERC20Upgradeable(_params.stablecoin).safeTransferFrom(
            msg.sender,
            address(this),
            _amountUSD
        );

        // Swap USD for token0
        // Single asset. Swap from USD directly to Token0
        _safeSwap(
            SafeSwapUni.SafeSwapParams({
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

        // Calculate resulting want token balance
        wantObtained = IERC20Upgradeable(_params.tokenZorroAddress).balanceOf(
            address(this)
        );

        // Transfer back to sender
        IERC20Upgradeable(_params.tokenZorroAddress).safeTransfer(
            msg.sender,
            wantObtained
        );
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be deposited beforehand)
    /// @param _params A ExchangeWantTokenForUSDParams struct
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return usdObtained Amount of USD token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        ExchangeWantTokenForUSDParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256 usdObtained) {
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
            SafeSwapUni.SafeSwapParams({
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
    ) internal override returns (uint256 wantObtained) {}
}
