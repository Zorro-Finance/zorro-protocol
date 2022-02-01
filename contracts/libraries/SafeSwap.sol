// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IAMMRouter02.sol";

import "./SafeMath.sol";

// TODO: Might want a V3 style router for better liquidity (e.g. Curve Finance/Uniswap V3) - create another function

/// @title SafeSwap: Library for safe swapping of ERC20 tokens
contract SafeSwap {
    /*
    Libraries
    */
    using SafeMath for uint256;

    /*
    Functions
    */
    /// @notice Safely swap tokens
    /// @param _uniRouter Uniswap V2 router
    /// @param _amountIn The quantity of the origin token to swap
    /// @param _slippageFactor The maximum slippage factor tolerated for this swap
    /// @param _path The path to take for the swap
    /// @param _to The destination to send the swapped token to
    /// @param _deadline How much time to allow for the transaction
    function safeSwap(
        IAMMRouter02 _uniRouter,
        uint256 _amountIn,
        uint256 _slippageFactor,
        address[] memory _path,
        address _to,
        uint256 _deadline
    ) public virtual {
        // TODO: Rather than calling getAmountsOut(), try to take in an input arg instead
        uint256[] memory amounts = _uniRouter.getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length.sub(1)];

        _uniRouter
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amountIn,
                amountOut.mul(_slippageFactor).div(1000),
                _path,
                _to,
                _deadline
            );
    }
}