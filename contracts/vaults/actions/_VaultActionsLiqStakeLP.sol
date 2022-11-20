// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "../../libraries/PriceFeed.sol";

import "./_VaultActions.sol";

import "./VaultActionsStandardAMM.sol";

import "../../interfaces/IAMMRouter02.sol";

abstract contract VaultActionsLiqStakeLP is VaultActions {
    /* Libs */
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;
    using PriceFeed for AggregatorV3Interface;

    /* Structs */

    struct ExchangeUSDForWantParams {
        address token0Address;
        address stablecoin;
        address liquidStakeToken;
        address liquidStakePool;
        address poolAddress;
        address wantAddress;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface liquidStakeTokenPriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] stablecoinToToken0Path;
        address[] liquidStakeToToken0Path;
    }

    struct ExchangeWantTokenForUSDParams {
        address token0Address;
        address stablecoin;
        address wantAddress;
        address poolAddress;
        address liquidStakeToken;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface liquidStakeTokenPriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] liquidStakeToToken0Path;
        address[] token0ToStablecoinPath;
    }

    /* Functions */

    /// @notice Deposits liquid stake on protocol
    /// @dev Must be implemented by inherited contracts
    function liquidStake(
        uint256 _amount,
        address _token0,
        address _liqStakeToken,
        address _liqStakePool
    ) public virtual;

    /// @notice Withdraws liquid stake on protocol
    /// @dev Must be implemented by inherited contracts
    function liquidUnstake(SafeSwapParams memory _swapParams) public virtual;

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be deposited beforehand)
    /// @param _params ExchangeWantTokenForUSDParams struct
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return returnedUSD Amount of USD token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        ExchangeWantTokenForUSDParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256 returnedUSD) {
        // Transfer amount IN
        IERC20Upgradeable(_params.wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Exit LP pool and get back sETH, WETH
        _exitPool(
            _amount,
            _maxMarketMovementAllowed,
            address(this),
            ExitPoolParams({
                token0: _params.liquidStakeToken,
                token1: _params.token0Address,
                poolAddress: _params.poolAddress,
                wantAddress: _params.wantAddress
            })
        );

        // Calc sETH balance
        uint256 _synthTokenBal = IERC20Upgradeable(_params.liquidStakeToken)
            .balanceOf(address(this));

        // Unstake sETH to get ETH
        liquidUnstake(
            SafeSwapParams({
                amountIn: _synthTokenBal,
                priceToken0: _params
                    .liquidStakeTokenPriceFeed
                    .getExchangeRate(),
                priceToken1: _params.token0PriceFeed.getExchangeRate(),
                token0: _params.liquidStakeToken,
                token1: _params.token0Address,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _params.liquidStakeToToken0Path,
                destination: address(this)
            })
        );

        // Calc ETH bal
        uint256 _token0Bal = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );

        // Swap ETH to USD
        _safeSwap(
            SafeSwapParams({
                amountIn: _token0Bal,
                priceToken0: _params.token0PriceFeed.getExchangeRate(),
                priceToken1: _params.stablecoinPriceFeed.getExchangeRate(),
                token0: _params.token0Address,
                token1: _params.stablecoin,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _params.token0ToStablecoinPath,
                destination: address(this)
            })
        );

        // Return USD amount
        returnedUSD = IERC20Upgradeable(_params.stablecoin).balanceOf(
            address(this)
        );

        // Transfer USD back to sender
        IERC20Upgradeable(_params.stablecoin).safeTransfer(
            msg.sender,
            returnedUSD
        );
    }

    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        ExchangeUSDForWantParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256 returnedWant) {
        // Transfer amount IN
        IERC20Upgradeable(_params.stablecoin).safeTransferFrom(
            msg.sender,
            address(this),
            _amountUSD
        );

        // Swap USD for ETH
        _safeSwap(
            SafeSwapParams({
                amountIn: _amountUSD,
                priceToken0: _params.stablecoinPriceFeed.getExchangeRate(),
                priceToken1: _params.token0PriceFeed.getExchangeRate(),
                token0: _params.stablecoin,
                token1: _params.token0Address,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _params.stablecoinToToken0Path,
                destination: address(this)
            })
        );

        // Get ETH balance
        uint256 _token0Bal = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );

        // Stake ETH (liquid staking)
        liquidStake(
            _token0Bal,
            _params.token0Address,
            _params.liquidStakeToken,
            _params.liquidStakePool
        );

        // Get bal of sETH
        uint256 _synthTokenBal = IERC20Upgradeable(_params.liquidStakeToken)
            .balanceOf(address(this));

        // Swap half of sETH to ETH
        _safeSwap(
            SafeSwapParams({
                amountIn: _synthTokenBal.div(2),
                priceToken0: _params.liquidStakeTokenPriceFeed.getExchangeRate(),
                priceToken1: _params.token0PriceFeed.getExchangeRate(),
                token0: _params.liquidStakeToken,
                token1: _params.token0Address,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _params.liquidStakeToToken0Path,
                destination: address(this)
            })
        );

        // Re-calc balances
        _synthTokenBal = IERC20Upgradeable(_params.liquidStakeToken)
            .balanceOf(address(this));
        _token0Bal = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );

        // Add liquidity to sETH-ETH pool
        _joinPool(
            _params.liquidStakeToken,
            _params.token0Address,
            _synthTokenBal,
            _token0Bal,
            _maxMarketMovementAllowed,
            address(this)
        );

        // Return bal of want tokens (same as Token0)
        returnedWant = IERC20Upgradeable(_params.wantAddress).balanceOf(address(this));

        // Transfer back to sender
        IERC20Upgradeable(_params.wantAddress).safeTransfer(msg.sender, returnedWant);
    }
}
