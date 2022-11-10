// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "../../libraries/PriceFeed.sol";

import "./VaultLibrary.sol";

import "../../interfaces/IAMMRouter02.sol";


/// @title Base library for VaultLiqStakeLP type vaults
library VaultLiqStakeLPLibrary {
    /* Libs */
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;
    using PriceFeed for AggregatorV3Interface;

    /* Structs */
    struct AddLiquidityParams {
        address uniRouterAddress;
        address token0Address;
        address liquidStakeToken;
        address[] liquidStakeToToken0Path;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface liquidStakeTokenPriceFeed;
        uint256 maxMarketMovementAllowed;
    }

    struct RemoveLiquidityParams {
        address uniRouterAddress;
        address poolAddress;
        address token0Address;
        address liquidStakeToken;
        uint256 maxMarketMovementAllowed;
    }

    /* Functions */
    /// @notice Supplies sAVAX token to Aave
    /// @param _amount Quantity of sAVAX (synth token) to swap and add as a liquidty
    /// @param _params AddLiquidityParams struct for adding liquidity of liquid staking token + native chain token
    function addLiquidity(uint256 _amount, AddLiquidityParams memory _params) public {
        // Allow spending
        IERC20Upgradeable(_params.liquidStakeToken).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _amount
        );

        // Swap half of sAVAX to wAVAX
        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(_params.liquidStakeToken).decimals(); // sAVAX
        _decimals[1] = ERC20Upgradeable(_params.token0Address).decimals(); // wAVAX

        // Swap
        VaultLibrary.safeSwap(
            _params.uniRouterAddress, 
            SafeSwapParams({
                amountIn: _amount.div(2),
                priceToken0: _params.liquidStakeTokenPriceFeed.getExchangeRate(),
                priceToken1: _params.token0PriceFeed.getExchangeRate(),
                token0: _params.liquidStakeToken,
                token1: _params.token0Address,
                maxMarketMovementAllowed: _params.maxMarketMovementAllowed,
                path: _params.liquidStakeToToken0Path,
                destination: address(this)
            }), 
            _decimals
        );
        
        // Calc balances
        uint256 _liqStakeBal = IERC20Upgradeable(_params.liquidStakeToken).balanceOf(address(this));
        uint256 _token0Bal = IERC20Upgradeable(_params.token0Address).balanceOf(address(this));

        // Add liqudity
        IAMMRouter02(_params.uniRouterAddress).addLiquidity(
            _params.token0Address,
            _params.liquidStakeToken,
            _token0Bal,
            _liqStakeBal,
            _token0Bal.mul(_params.maxMarketMovementAllowed).div(1000),
            _liqStakeBal.mul(_params.maxMarketMovementAllowed).div(1000),
            address(this),
            block.timestamp.add(600)
        );
    }

    /// @notice Removes liquidity from AMM pool and withdraws to sAVAX
    /// @param _amount Quantity of LP token to exchange
    /// @param _params RemoveLiquidityParams struct
    function removeLiquidity(uint256 _amount, RemoveLiquidityParams memory _params) public {
        VaultLibraryStandardAMM.exitPool(
            _amount,
            _params.maxMarketMovementAllowed,
            address(this),
            VaultLibraryStandardAMM.ExitPoolParams({
                token0: _params.liquidStakeToken,
                token1: _params.token0Address,
                poolAddress: _params.poolAddress,
                uniRouterAddress: _params.uniRouterAddress,
                wantAddress: _params.poolAddress
            })
        );
    }
}
