// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IAMMRouter02.sol";

import "../interfaces/ICurveMetaPool.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/IBalancerVault.sol";


/// @title SafeSwapUni: Library for safe swapping of ERC20 tokens for Uniswap/Pancakeswap style protocols
library SafeSwapUni {
    /* Libraries */
    using SafeMath for uint256;

    /* Functions */
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
    /* Libraries */
    using SafeMath for uint256;

    /* Functions */
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

/// @title SafeSwapBalancer: Library for safe swapping of ERC20 tokens for Balancer style protocols (e.g. Acryptos)
library SafeSwapBalancer {
    /* Libraries */
    using SafeMath for uint256;

    /* Functions */
    /// @notice Safely swaps one asset for another using a provided Balancer pool
    /// @param _balancerVault Acryptos/Balancer vault (contract for performing swaps)
    /// @param _poolId Address of the pool to perform swaps
    /// @param _amountIn The amount of a certain token provided
    /// @param _assetIn The address of the token provided
    /// @param _assetOut The address of the token desired
    /// @param _slippageFactor The tolerable slippage expressed as the numerator over 1000. E.g. 950 => 950/1000 => 5% slippage tolerance
    /// @param _tokenAWeightBasisPoints The percent (in basis points) of Token A's weight in the balancer pool
    /// @param _tokenBWeightBasisPoints The percent (in basis points) of Token B's weight in the balancer pool
    /// @param _destination The address to send swapped funds to (must be payable)
    function safeSwap(
        IBalancerVault _balancerVault,
        bytes32 _poolId,
        uint256 _amountIn,
        address _assetIn,
        address _assetOut,
        uint256 _slippageFactor,
        uint256 _tokenAWeightBasisPoints,
        uint256 _tokenBWeightBasisPoints,
        address _destination
    ) public {
        // Determine the limit based on the exchange rate
        uint256 limit = _getExchangeRate(_balancerVault, _poolId, _assetOut, _assetIn, _tokenAWeightBasisPoints, _tokenBWeightBasisPoints)
            .mul(_slippageFactor)
            .div(1000);
        // Swap Earned token to token0
        _balancerVault.swap(
            SingleSwap({
                poolId: _poolId,
                kind: SwapKind.GIVEN_IN,
                assetIn: IAsset(_assetIn),
                assetOut: IAsset(_assetOut),
                amount: _amountIn,
                userData: ""
            }),
            FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(_destination),
                toInternalBalance: false
            }),
            limit,
            block.timestamp.add(600)
        );
    }

    /// @notice Calculates exchange rate of token B per token A. Note: Ignores swap fees!
    /// @param _balancerVault Acryptos/Balancer vault
    /// @param _poolId Address of the pool to perform swaps
    /// @param _tokenA token A address
    /// @param _tokenB token B address
    /// @param _tokenAWeightBasisPoints The percent (in basis points) of Token A's weight in the balancer pool
    /// @param _tokenBWeightBasisPoints The percent (in basis points) of Token B's weight in the balancer pool
    /// @return exhange rate of token B per token A
    function _getExchangeRate(
        IBalancerVault _balancerVault,
        bytes32 _poolId,
        address _tokenA, 
        address _tokenB,
        uint256 _tokenAWeightBasisPoints,
        uint256 _tokenBWeightBasisPoints
    ) internal returns (uint256) {
        // Calculate current balances of each token (Earned, and token0)
        (uint256 cashB, , , ) = _balancerVault
            .getPoolTokenInfo(
                _poolId,
                IERC20(_tokenB)
            );
        (uint256 cashA, , , ) = _balancerVault
            .getPoolTokenInfo(
                _poolId,
                IERC20(_tokenA)
            );
        // Return exchange rate, accounting for weightings
        return
            (cashA.div(_tokenAWeightBasisPoints)).div(
                cashB.div(_tokenBWeightBasisPoints)
            );
    }
}