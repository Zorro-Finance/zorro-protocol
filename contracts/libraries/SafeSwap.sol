// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IAMMRouter02.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "../interfaces/IBalancerVault.sol";

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
                .mul(10**(_decimals[1] - _decimals[0]))
                .div(_priceTokenOut.mul(1000));
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
                .mul(10**(_decimals[1] - _decimals[0]))
                .div(1000);
    }
}

/// @title SafeSwapBalancer: Library for safe swapping of ERC20 tokens for Balancer style protocols (e.g. Acryptos)
library SafeSwapBalancer {
    /* Libraries */
    using SafeMathUpgradeable for uint256;

    /* Functions */
    /// @notice Safely swaps one asset for another using a provided Balancer pool
    /// @param _balancerVault Acryptos/Balancer vault (contract for performing swaps)
    /// @param _poolId Address of the pool to perform swaps
    /// @param _swapParams SafeSwapParams for swap
    /// @param _decimals The number of decimals for _amountIn, _amountOut
    function safeSwap(
        IBalancerVault _balancerVault,
        bytes32 _poolId,
        SafeSwapParams memory _swapParams,
        uint8[] memory _decimals
    ) internal {
        // Requirements
        require(_decimals.length == 2, "invalid dec");
        // Calculate min amount out
        uint256 _amountOut;
        if (_swapParams.priceToken0 == 0 || _swapParams.priceToken1 == 0) {
            // If no exchange rates provided, use on-chain functions provided by router (not ideal)]
            _amountOut = _swapParams
                .amountIn
                .mul(
                    _getBalancerExchangeRate(
                        _balancerVault,
                        _poolId,
                        _swapParams
                    )
                )
                .mul(_swapParams.maxMarketMovementAllowed)
                .mul(10**(_decimals[1] - _decimals[0]))
                .div(uint256(1000).mul(1e12));
        } else {
            // Calculate amountOut based on provided exchange rates
            _amountOut = _swapParams
                .amountIn
                .mul(_swapParams.priceToken0)
                .mul(_swapParams.maxMarketMovementAllowed)
                .mul(10**(_decimals[1] - _decimals[0]))
                .div(_swapParams.priceToken1.mul(1000));
        }

        // Swap Earned token to token0
        _balancerVault.swap(
            SingleSwap({
                poolId: _poolId,
                kind: SwapKind.GIVEN_IN,
                assetIn: IAsset(_swapParams.token0),
                assetOut: IAsset(_swapParams.token1),
                amount: _swapParams.amountIn,
                userData: ""
            }),
            FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(_swapParams.destination),
                toInternalBalance: false
            }),
            _amountOut,
            block.timestamp.add(600)
        );
    }

    /// @notice Calculates exchange rate of token1 per token0, times 1e12. Note: Ignores swap fees!
    /// @param _swapParams SafeSwapParams for swap
    function _getBalancerExchangeRate(
        IBalancerVault _balancerVault,
        bytes32 _poolId,
        SafeSwapParams memory _swapParams
    ) internal returns (uint256) {
        // Calculate current balances of each token
        (uint256 cash1, , , ) = _balancerVault.getPoolTokenInfo(
            _poolId,
            IERC20(_swapParams.token1)
        );
        (uint256 cash0, , , ) = _balancerVault.getPoolTokenInfo(
            _poolId,
            IERC20(_swapParams.token0)
        );

        // Return exchange rate, accounting for weightings, mul by 1e12 for float accuracy
        return
            cash1.mul(_swapParams.token0Weight).mul(1e12).div(
                cash0.mul(_swapParams.token1Weight)
            );
    }
}

struct SafeSwapParams {
    uint256 amountIn;
    uint256 priceToken0;
    uint256 priceToken1;
    address token0;
    address token1;
    uint256 token0Weight;
    uint256 token1Weight;
    uint256 maxMarketMovementAllowed;
    address[] path;
    address destination;
}
