// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IAMMRouter02.sol";

import "../interfaces/ICurveMetaPool.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// TODO: Might want a V3 style router for better liquidity (e.g. Curve Finance/Uniswap V3) - create another function

/// @title SafeSwapUni: Library for safe swapping of ERC20 tokens for Uniswap/Pancakeswap style protocols
library SafeSwapUni {
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
    ) public {
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

/// @title SafeSwapCurve: Library for safe swapping of ERC20 tokens for Curve style protocols
library SafeSwapCurve {
    /*
    Libraries
    */
    using SafeMath for uint256;

    /*
    Functions
    */
    /// @notice Safely swap tokens
    /// @param _curvePool Curve pool contract
    /// @param _amountIn The quantity of the origin token to swap
    /// @param _slippageFactor The maximum slippage factor tolerated for this swap
    /// @param _i The index of the token to transfer from
    /// @param _j The index of the token to transfer to
    function safeSwap(
        ICurveMetaPool _curvePool,
        uint256 _amountIn,
        uint256 _slippageFactor,
        int128 _i,
        int128 _j
    ) public {
        // TODO: Rather than calling get_dy(), try to take in an input arg instead
        // Determine minimum amount to get out based on input, accounting for slippage
        uint256 _min_dy = _curvePool.get_dy(_i, _j, _amountIn).mul(_slippageFactor).div(1000);
        // Exchange underlying and return swapped tokens to this address
        _curvePool.exchange_underlying(_i, _j, _amountIn, _min_dy);
    }
}