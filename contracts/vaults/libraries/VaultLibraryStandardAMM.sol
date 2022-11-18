// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../libraries/SafeSwap.sol";

import "../../libraries/PriceFeed.sol";

import "../../interfaces/Alpaca/IAlpacaFairLaunch.sol";

import "../../interfaces/Alpaca/IAlpacaVault.sol";

import "../../interfaces/IAMMRouter02.sol";

import "./VaultLibrary.sol";

library VaultLibraryStandardAMM {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /// @notice Adds liquidity to the pool of this contract
    /// @param _token0 The address of Token0
    /// @param _token1 The address of Token1
    /// @param _token0Amt Quantity of Token0 to add
    /// @param _token1Amt Quantity of Token1 to add
    /// @param _uniRouterAddress The address of the uni style router
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _recipient The recipient of the LP token
    function joinPool(
        address _token0,
        address _token1,
        uint256 _token0Amt,
        uint256 _token1Amt,
        address _uniRouterAddress,
        uint256 _maxMarketMovementAllowed,
        address _recipient
    ) public {
        IAMMRouter02(_uniRouterAddress).addLiquidity(
            _token0,
            _token1,
            _token0Amt,
            _token1Amt,
            _token0Amt.mul(_maxMarketMovementAllowed).div(1000),
            _token1Amt.mul(_maxMarketMovementAllowed).div(1000),
            _recipient,
            block.timestamp.add(600)
        );
    }

    struct ExitPoolParams {
        address token0;
        address token1;
        address poolAddress;
        address uniRouterAddress;
        address wantAddress;
    }

    /// @notice Removes liquidity from a pool and sends tokens back to this address
    /// @param _amountLP The amount of LP (Want) tokens to remove
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _recipient The recipient of the underlying tokens at pool exit
    function exitPool(
        uint256 _amountLP,
        uint256 _maxMarketMovementAllowed,
        address _recipient,
        ExitPoolParams memory _exitPoolParams
    ) public {
        // Init
        uint256 _amount0Min;
        uint256 _amount1Min;
        // Get total supply and calculate min amounts desired based on slippage
        uint256 _totalSupply = IERC20Upgradeable(_exitPoolParams.poolAddress)
            .totalSupply();

        {
            _amount0Min = _calcMinAmt(
                _amountLP,
                _exitPoolParams.token0,
                _exitPoolParams.poolAddress,
                _totalSupply,
                _maxMarketMovementAllowed
            );
            _amount1Min = _calcMinAmt(
                _amountLP,
                _exitPoolParams.token1,
                _exitPoolParams.poolAddress,
                _totalSupply,
                _maxMarketMovementAllowed
            );
        }

        // Approve
        IERC20Upgradeable(_exitPoolParams.wantAddress).safeIncreaseAllowance(
            _exitPoolParams.uniRouterAddress,
            _amountLP
        );

        // Remove liquidity
        IAMMRouter02(_exitPoolParams.uniRouterAddress).removeLiquidity(
            _exitPoolParams.token0,
            _exitPoolParams.token1,
            _amountLP,
            _amount0Min,
            _amount1Min,
            _recipient,
            block.timestamp.add(600)
        );
    }

    /// @notice Calculates minimum amount out for exiting LP pool
    /// @param _amountLP LP token qty
    /// @param _token Address of one of the tokens in the pair
    /// @param _poolAddress Address of LP pair
    /// @param _totalSupply Total supply of LP tokens
    /// @param _maxMarketMovementAllowed Slippage (990 = 1% etc.)
    function _calcMinAmt(
        uint256 _amountLP,
        address _token,
        address _poolAddress,
        uint256 _totalSupply,
        uint256 _maxMarketMovementAllowed
    ) internal view returns (uint256) {
        uint256 _balance = IERC20Upgradeable(_token).balanceOf(_poolAddress);
        return
            (_amountLP.mul(_balance).div(_totalSupply))
                .mul(_maxMarketMovementAllowed)
                .div(1000);
    }

    struct AddLiqAndBurnParams {
        address zorro;
        address zorroLPPoolOtherToken;
        address uniRouterAddress;
        address burnAddress;
    }

    /// @notice Adds liquidity and burns the associated LP token
    /// @param _maxMarketMovementAllowed Slippage factor (990 = 1% etc.)
    /// @param _params AddLiqAndBurnParams containing addresses
    function addLiqAndBurn(
        uint256 _maxMarketMovementAllowed,
        AddLiqAndBurnParams memory _params
    ) public {
        // Enter LP pool and send received token to the burn address
        uint256 zorroTokenAmt = IERC20Upgradeable(_params.zorro).balanceOf(
            address(this)
        );
        uint256 otherTokenAmt = IERC20Upgradeable(_params.zorroLPPoolOtherToken)
            .balanceOf(address(this));

        IERC20Upgradeable(_params.zorro).safeIncreaseAllowance(
            _params.uniRouterAddress,
            zorroTokenAmt
        );
        IERC20Upgradeable(_params.zorroLPPoolOtherToken).safeIncreaseAllowance(
            _params.uniRouterAddress,
            otherTokenAmt
        );

        IAMMRouter02(_params.uniRouterAddress).addLiquidity(
            _params.zorro,
            _params.zorroLPPoolOtherToken,
            zorroTokenAmt,
            otherTokenAmt,
            zorroTokenAmt.mul(_maxMarketMovementAllowed).div(1000),
            otherTokenAmt.mul(_maxMarketMovementAllowed).div(1000),
            _params.burnAddress,
            block.timestamp.add(600)
        );
    }

    struct SwapUSDAddLiqParams {
        address stablecoin;
        address token0Address;
        address token1Address;
        address uniRouterAddress;
        AggregatorV3Interface stablecoinPriceFeed;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface token1PriceFeed;
        address[] stablecoinToToken0Path;
        address[] stablecoinToToken1Path;
        address wantAddress;
    }

    /// @notice Performs necessary operations to convert USD into Want token and transfer back to sender
    /// @param _amountUSD The amount of USD to exchange for Want token (must already be deposited on this contract)
    /// @param _params A SwapUSDAddLiqParams struct
    /// @param _maxMarketMovementAllowed Slippage (990 = 1% etc.)
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        SwapUSDAddLiqParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256) {
        // Get balance of deposited USD
        uint256 _balUSD = IERC20Upgradeable(_params.stablecoin)
            .balanceOf(address(this));
        // Check that USD was actually deposited
        require(_amountUSD > 0, "dep<=0");
        require(_amountUSD <= _balUSD, "amt>bal");

        // Determine exchange rates using price feed oracle
        uint256[] memory _priceTokens0 = new uint256[](2);
        _priceTokens0[0] = _params.stablecoinPriceFeed.getExchangeRate();
        _priceTokens0[1] = _params.token0PriceFeed.getExchangeRate();
        uint256[] memory _priceTokens1 = new uint256[](2);
        _priceTokens1[0] = _priceTokens0[0];
        _priceTokens1[1] = _params.token1PriceFeed.getExchangeRate();

        // Get decimal info
        uint8[] memory _decimals0 = new uint8[](2);
        _decimals0[0] = ERC20Upgradeable(_params.stablecoin).decimals();
        _decimals0[1] = ERC20Upgradeable(_params.token0Address).decimals();
        uint8[] memory _decimals1 = new uint8[](2);
        _decimals1[0] = _decimals0[0];
        _decimals1[1] = ERC20Upgradeable(_params.token1Address).decimals();

        // Increase allowance
        IERC20Upgradeable(_params.stablecoin).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _amountUSD
        );

        // Swap USD for token0
        if (_params.token0Address != _params.stablecoin) {
            IAMMRouter02(_params.uniRouterAddress).safeSwap(
                _amountUSD.div(2),
                _priceTokens0,
                _maxMarketMovementAllowed,
                _params.stablecoinToToken0Path,
                _decimals0,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Swap USD for token1 (if applicable)
        if (_params.token1Address != _params.stablecoin) {
            IAMMRouter02(_params.uniRouterAddress).safeSwap(
                _amountUSD.div(2),
                _priceTokens1,
                _maxMarketMovementAllowed,
                _params.stablecoinToToken1Path,
                _decimals1,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Deposit token0, token1 into LP pool to get Want token (i.e. LP token)
        uint256 _token0Amt = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );
        uint256 _token1Amt = IERC20Upgradeable(_params.token1Address).balanceOf(
            address(this)
        );
        IERC20Upgradeable(_params.token0Address).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _token0Amt
        );
        IERC20Upgradeable(_params.token1Address).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _token1Amt
        );

        // Add liquidity
        joinPool(
            _params.token0Address,
            _params.token1Address,
            _token0Amt,
            _token1Amt,
            _params.uniRouterAddress,
            _maxMarketMovementAllowed,
            msg.sender
        );

        // Calculate resulting want token balance
        return IERC20Upgradeable(_params.wantAddress).balanceOf(msg.sender);
    }

    struct ExchWantToUSDParams {
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface token1PriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address token0Address;
        address token1Address;
        address stablecoin;
        address uniRouterAddress;
        address[] token0ToStablecoinPath;
        address[] token1ToStablecoinPath;
        address wantAddress;
        address poolAddress;
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal, transfers back to sender
    /// @param _amount The Want token quantity to exchange
    /// @param _params ExchWantToUSDParams struct
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of USD token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        ExchWantToUSDParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) public returns (uint256) {
        // Preflight checks
        require(_amount > 0, "negWant");

        // Safely transfer Want token from sender
        IERC20Upgradeable(_params.wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Exit LP pool
        exitPool(
            _amount,
            _maxMarketMovementAllowed,
            address(this),
            ExitPoolParams({
                token0: _params.token0Address,
                token1: _params.token1Address,
                poolAddress: _params.poolAddress,
                uniRouterAddress: _params.uniRouterAddress,
                wantAddress: _params.wantAddress
            })
        );

        // Swap tokens back to USD
        uint256 _token0Amt = IERC20Upgradeable(_params.token0Address).balanceOf(
            address(this)
        );
        uint256 _token1Amt = IERC20Upgradeable(_params.token1Address).balanceOf(
            address(this)
        );

        _swapTokensForUSD(
            _token0Amt,
            _token1Amt,
            _params,
            _maxMarketMovementAllowed
        );

        // Calculate USD balance
        return IERC20Upgradeable(_params.stablecoin).balanceOf(msg.sender);
    }

    function _swapTokensForUSD(
        uint256 _token0Amt,
        uint256 _token1Amt,
        ExchWantToUSDParams memory _params,
        uint256 _maxMarketMovementAllowed
    ) internal {
        // Increase allowance
        IERC20Upgradeable(_params.token0Address).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _token0Amt
        );
        IERC20Upgradeable(_params.token1Address).safeIncreaseAllowance(
            _params.uniRouterAddress,
            _token1Amt
        );

        // Get decimal info
        uint8[] memory _decimals0 = new uint8[](2);
        _decimals0[0] = ERC20Upgradeable(_params.token0Address).decimals();
        _decimals0[1] = ERC20Upgradeable(_params.stablecoin).decimals();
        uint8[] memory _decimals1 = new uint8[](2);
        _decimals1[0] = ERC20Upgradeable(_params.token1Address).decimals();
        _decimals1[1] = _decimals0[1];

        // Exchange rates
        uint256[] memory _priceTokens0 = new uint256[](2);
        _priceTokens0[0] = _params.token0PriceFeed.getExchangeRate();
        _priceTokens0[1] = _params.stablecoinPriceFeed.getExchangeRate();
        uint256[] memory _priceTokens1 = new uint256[](2);
        _priceTokens1[0] = _params.token1PriceFeed.getExchangeRate();
        _priceTokens1[1] = _priceTokens0[1];

        // Swap token0 for USD
        if (_params.token0Address != _params.stablecoin) {
            IAMMRouter02(_params.uniRouterAddress).safeSwap(
                _token0Amt,
                _priceTokens0,
                _maxMarketMovementAllowed,
                _params.token0ToStablecoinPath,  
                _decimals0,
                msg.sender,
                block.timestamp.add(600)
            );
        }

        // Swap token1 for USD
        if (_params.token1Address != _params.stablecoin) {
            IAMMRouter02(_params.uniRouterAddress).safeSwap(
                _token1Amt,
                _priceTokens1,
                _maxMarketMovementAllowed,
                _params.token1ToStablecoinPath,
                _decimals1,
                msg.sender,
                block.timestamp.add(600)
            );
        }
    }
}
