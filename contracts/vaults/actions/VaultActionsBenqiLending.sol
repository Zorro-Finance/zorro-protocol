// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../libraries/SafeSwap.sol";

import "../../libraries/PriceFeed.sol";

import "../../interfaces/Benqi/IUnitroller.sol";

import "../../interfaces/Lending/ILendingToken.sol";

import "./_VaultActionsLending.sol";

contract VaultActionsBenqiLending is VaultActionsLending {
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
        address poolAddress;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] stablecoinToToken0Path;
    }

    struct ExchangeWantTokenForUSDParams {
        address token0Address;
        address stablecoin;
        address poolAddress;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] token0ToStablecoinPath;
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
        if (_params.token0Address != _params.stablecoin) {
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

        // Swap Token0 -> BUSD
        if (_params.token0Address != _params.stablecoin) {
            _safeSwap(
                SafeSwapParams({
                    amountIn: _amount,
                    priceToken0: _params.token0PriceFeed.getExchangeRate(),
                    priceToken1: _params.stablecoinPriceFeed.getExchangeRate(),
                    token0: _params.token0Address,
                    token1: _params.stablecoin,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: _params.token0ToStablecoinPath,
                    destination: address(this)
                })
            );
        }

        // Calculate USD balance
        return IERC20Upgradeable(_params.stablecoin).balanceOf(msg.sender);
    }

    /* Utilities */

    /// @notice Gets loan collateral factor from lending protocol
    /// @return collFactor The collateral factor %. TODO: Specify denominator (1e18?) Check against consuming logic.
    /// @param _comptrollerAddress Address of the ApeLending Unitroller proxy
    /// @param _poolAddress Address of the lending pool
    function collateralFactor(address _comptrollerAddress, address _poolAddress)
        public
        view
        override
        returns (uint256 collFactor)
    {
        (, uint256 _collateralFactor, ) = IUnitrollerBenqi(_comptrollerAddress)
            .markets(_poolAddress);
        return _collateralFactor;
    }
}
