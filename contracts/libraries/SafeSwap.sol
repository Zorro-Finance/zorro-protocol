// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IAMMRouter02.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

/// @title SafeSwapUni: Library for safe swapping of ERC20 tokens for Uniswap/Pancakeswap style protocols
library SafeSwapUni {
    /* Libraries */
    using SafeMathUpgradeable for uint256;

    /* Functions */
    /// @notice Safely swap tokens
    /// @param _uniRouter Uniswap V2 router
    /// @param _amountIn The quantity of the origin token to swap
    /// @param _priceTokens Array of prices of tokenIn in USD, times 1e12, then tokenOut
    /// @param _slippageFactor The maximum slippage factor tolerated for this swap
    /// @param _path The path to take for the swap
    /// @param _decimals The number of decimals for _amountIn, _amountOut
    /// @param _to The destination to send the swapped token to
    /// @param _deadline How much time to allow for the transaction
    function safeSwap(
        IAMMRouter02 _uniRouter,
        uint256 _amountIn,
        uint256[] memory _priceTokens,
        uint256 _slippageFactor,
        address[] memory _path,
        uint8[] memory _decimals,
        address _to,
        uint256 _deadline
    ) internal {
        // Requirements
        require(_decimals.length == 2, "invalid dec");
        // Calculate min amount out (account for slippage)
        uint256 _amountOut;

        if (_priceTokens[0] == 0 || _priceTokens[1] == 0) {
            // If no exchange rates provided, use on-chain functions provided by router (not ideal)
            _amountOut = _getAmountOutWithoutExchangeRates(
                _uniRouter,
                _amountIn,
                _path,
                _slippageFactor,
                _decimals
            );
        } else {
            _amountOut = _getAmountOutWithExchangeRates(
                _amountIn,
                _priceTokens[0],
                _priceTokens[1],
                _slippageFactor,
                _decimals
            );
        }
        // Swap
        _uniRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn,
            _amountOut,
            _path,
            _to,
            _deadline
        );
    }

    /// @notice Gets amounts out using provided exchange rates
    function _getAmountOutWithExchangeRates(
        uint256 _amountIn,
        uint256 _priceTokenIn,
        uint256 _priceTokenOut,
        uint256 _slippageFactor,
        uint8[] memory _decimals
    ) internal pure returns (uint256) {
        return
            _amountIn
                .mul(_priceTokenIn)
                .mul(_slippageFactor)
                .mul(10**_decimals[1])
                .div(_priceTokenOut.mul(1000).mul(10**_decimals[0]));
    }

    /// @notice Gets amounts out when exchange rates are not provided (uses router)
    function _getAmountOutWithoutExchangeRates(
        IAMMRouter02 _uniRouter,
        uint256 _amountIn,
        address[] memory _path,
        uint256 _slippageFactor,
        uint8[] memory _decimals
    ) internal view returns (uint256) {
        uint256[] memory amounts = _uniRouter.getAmountsOut(_amountIn, _path);
        return
            amounts[amounts.length.sub(1)]
                .mul(_slippageFactor)
                .mul(10**_decimals[1])
                .div((10**_decimals[0]).mul(1000));
    }
}

// TODO: Move this into library itself, above?
struct SafeSwapParams {
    uint256 amountIn;
    uint256 priceToken0;
    uint256 priceToken1;
    address token0;
    address token1;
    uint256 maxMarketMovementAllowed;
    address[] path;
    address destination;
}
