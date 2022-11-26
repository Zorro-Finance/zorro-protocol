// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/Stargate/IStargateRouter.sol";

import "../../interfaces/Stargate/IStargateLPStaking.sol";

import "../../interfaces/Zorro/Vaults/IVaultStargate.sol";

import "./_VaultActions.sol";

contract VaultActionsStargate is VaultActions {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Structs */

    struct ExchangeUSDForWantParams {
        address stablecoin;
        address token0Address;
        address tokenZorroAddress;
        address wantAddress;
        address stargateRouter;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] stablecoinToToken0Path;
        uint16 stargatePoolId;
    }

    struct ExchangeWantTokenForUSDParams {
        address stablecoin;
        address token0Address;
        address wantAddress;
        address stargateRouter;
        AggregatorV3Interface token0PriceFeed;
        AggregatorV3Interface stablecoinPriceFeed;
        address[] token0ToStablecoinPath;
        uint16 stargatePoolId;
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
        if (_params.token0Address != _params.stablecoin) {
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
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

        // Increase allowance
        IERC20Upgradeable(_params.token0Address).safeIncreaseAllowance(
            _params.stargateRouter,
            _token0Bal
        );

        // Deposit token to get Want token
        IStargateRouter(_params.stargateRouter).addLiquidity(
            _params.stargatePoolId,
            _token0Bal,
            address(this)
        );

        // Calculate resulting want token balance
        wantObtained = IERC20Upgradeable(_params.wantAddress).balanceOf(
            address(this)
        );

        // Transfer back to sender
        IERC20Upgradeable(_params.wantAddress).safeTransfer(
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
        IERC20Upgradeable(_params.wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Approve
        IERC20Upgradeable(_params.wantAddress).safeIncreaseAllowance(
            _params.stargateRouter,
            _amount
        );

        // Withdraw Want token to get Token0
        IStargateRouter(_params.stargateRouter).instantRedeemLocal(
            _params.stargatePoolId,
            _amount,
            address(this)
        );

        if (_params.token0Address != _params.stablecoin) {
            // Get Token0 balance
            uint256 _token0Bal = IERC20Upgradeable(_params.token0Address)
                .balanceOf(address(this));

            // Swap Token0 -> USD
            _safeSwap(
                SafeSwapUni.SafeSwapParams({
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
        }

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
    ) internal override returns (uint256 wantObtained) {
        // Prep
        IVaultStargate _vault = IVaultStargate(msg.sender);

        address _earnedAddress = _vault.earnedAddress();
        address _token0Address = _vault.token0Address();
        address _wantAddress = _vault.wantAddress();
        address _stargateRouter = _vault.stargateRouter();
        AggregatorV3Interface _token0PriceFeed = _vault.priceFeeds(_token0Address);
        AggregatorV3Interface _earnTokenPriceFeed = _vault.priceFeeds(_earnedAddress);
        uint16 _stargatePoolId = _vault.stargatePoolId();

        // Swap Earn token for single asset token (STG -> token0)
        _safeSwap(
            SafeSwapUni.SafeSwapParams({
                amountIn: _remainingEarnAmt,
                priceToken0: _earnTokenPriceFeed.getExchangeRate(),
                priceToken1: _token0PriceFeed.getExchangeRate(),
                token0: _earnedAddress,
                token1: _token0Address,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _getSwapPath(_earnedAddress, _token0Address),
                destination: address(this)
            })
        );

        // Redeposit single asset token to get Want token
        // Get new Token0 balance
        uint256 _token0Bal = IERC20Upgradeable(_token0Address).balanceOf(
            address(this)
        );

        // Safe approve
        IERC20Upgradeable(_token0Address).safeIncreaseAllowance(
            _stargateRouter,
            _token0Bal
        );

        // Deposit token to get Want token
        IStargateRouter(_stargateRouter).addLiquidity(
            _stargatePoolId,
            _token0Bal,
            address(this)
        );

        // Calc want balance
        wantObtained = IERC20Upgradeable(_wantAddress).balanceOf(address(this));

        // Transfer want token to destination
        IERC20Upgradeable(_wantAddress).safeTransfer(
            _destination,
            wantObtained
        );
    }
}
