// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_VaultBaseLiqStakeLP.sol";

import "./libraries/VaultLiqStakeLPLibrary.sol";

import "./libraries/VaultBenqiLiqStakeLPLibrary.sol";

/// @title Vault contract for Benqi liquid staking + LP strategy
contract VaultBenqiLiqStakeLP is VaultBaseLiqStakeLP {
    /* Libraries */
    using SafeERC20Upgradeable for IERC20Upgradeable; 
    using PriceFeed for AggregatorV3Interface;
    using SafeMathUpgradeable for uint256;
    using SafeSwapUni for IAMMRouter02;

    /* Investment Actions */

    /// @notice Deposits liquid stake on Benqi protocol
    /// @param _amount The amount of AVAX to liquid stake
    function _liquidStake(uint256 _amount) internal override whenNotPaused {
        VaultBenqiLiqStakeLPLibrary.liquidStake(_amount, token0Address, liquidStakeToken);
    }

    /// @notice Withdraws liquid stake on Benqi protocol
    /// @param _amount The amount of AVAX to unstake
    function _liquidUnstake(uint256 _amount) internal override whenNotPaused {
        VaultBenqiLiqStakeLPLibrary.liquidUnstake(
            uniRouterAddress,
            SafeSwapParams({
                amountIn: _amount,
                priceToken0: liquidStakeTokenPriceFeed.getExchangeRate(),
                priceToken1: token0PriceFeed.getExchangeRate(),
                token0: liquidStakeToken,
                token1: token0Address,
                maxMarketMovementAllowed: maxMarketMovementAllowed,
                path: liquidStakeToToken0Path,
                destination: address(this)
            })
        );
    }

    /* Functions */
    /// @notice Supplies sAVAX token to AMM
    /// @param _amount Quantity of sAVAX (synth token) to swap and add as a liquidty
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    function _addLiquidity(uint256 _amount, uint256 _maxMarketMovementAllowed) internal {
        VaultLiqStakeLPLibrary.addLiquidity(
            _amount, 
            VaultLiqStakeLPLibrary.AddLiquidityParams({
                uniRouterAddress: uniRouterAddress,
                token0Address: token0Address,
                liquidStakeToken: liquidStakeToken,
                liquidStakeToToken0Path: liquidStakeToToken0Path,
                token0PriceFeed: token0PriceFeed,
                liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                maxMarketMovementAllowed: _maxMarketMovementAllowed
            })
        );
    }

    /// @notice Performs necessary operations to convert USD into Want token
    /// @param _amountUSD The USD quantity to exchange (must already be deposited)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        return VaultBenqiLiqStakeLPLibrary.exchangeUSDForWantToken(
            _amountUSD, 
            VaultBenqiLiqStakeLPLibrary.ExchangeUSDForWantParams({
                token0Address: token0Address,
                stablecoin: defaultStablecoin,
                liquidStakeToken: liquidStakeToken,
                token0PriceFeed: token0PriceFeed,
                liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                stablecoinPriceFeed: stablecoinPriceFeed,
                uniRouterAddress: uniRouterAddress,
                stablecoinToToken0Path: stablecoinToToken0Path,
                liquidStakeToToken0Path: liquidStakeToToken0Path,
                poolAddress: poolAddress,
                wantAddress: wantAddress
            }), 
            _maxMarketMovementAllowed
        );
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be deposited beforehand)
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return returnedUSD Amount of USD token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    )
        public
        virtual
        override
        onlyZorroController
        whenNotPaused
        returns (uint256 returnedUSD)
    {
        return VaultBenqiLiqStakeLPLibrary.exchangeWantTokenForUSD(
            _amount, 
            VaultBenqiLiqStakeLPLibrary.ExchangeWantTokenForUSDParams({
                token0Address: token0Address,
                stablecoin: defaultStablecoin,
                wantAddress: wantAddress,
                poolAddress: poolAddress,
                liquidStakeToken: liquidStakeToken,
                token0PriceFeed: token0PriceFeed,
                liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                stablecoinPriceFeed: stablecoinPriceFeed,
                liquidStakeToToken0Path: liquidStakeToToken0Path, 
                token0ToStablecoinPath: token0ToStablecoinPath, 
                uniRouterAddress: uniRouterAddress
            }), 
            _maxMarketMovementAllowed
        );
    }

    /// @notice The main compounding (earn) function. Reinvests profits since the last earn event.
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    function earn(uint256 _maxMarketMovementAllowed)
        public
        virtual
        override
        nonReentrant
        whenNotPaused
    {
        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // Harvest farm tokens
        _unfarm(0);

        // Get the balance of the Earned token on this contract
        uint256 _earnedAmt = IERC20Upgradeable(earnedAddress).balanceOf(address(this));

        // Require pending rewards in order to continue
        require(_earnedAmt > 0, "0earn");

        // Create rates struct
        VaultLibrary.ExchangeRates memory _rates;
        uint256[] memory _priceTokens0 = new uint256[](2);
        uint256[] memory _priceTokens1 = new uint256[](2);
        {
            _rates = VaultLibrary.ExchangeRates({
                earn: earnTokenPriceFeed.getExchangeRate(),
                ZOR: ZORPriceFeed.getExchangeRate(),
                lpPoolOtherToken: lpPoolOtherTokenPriceFeed.getExchangeRate(),
                stablecoin: stablecoinPriceFeed.getExchangeRate()
            });
            _priceTokens0[0] = _rates.earn;
            _priceTokens0[1] = token0PriceFeed.getExchangeRate();
            _priceTokens1[0] = _rates.earn;
            _priceTokens1[1] = token1PriceFeed.getExchangeRate();
        }

        // Calc remainder
        uint256 _remainingAmt;

        {
            // Distribute fees
            uint256 _controllerFee = _distributeFees(_earnedAmt);

            // Buyback & rev share
            (uint256 _buybackAmt, uint256 _revShareAmt) = _buyBackAndRevShare(
                _earnedAmt,
                _maxMarketMovementAllowed,
                _rates
            );

            _remainingAmt = _earnedAmt.sub(_controllerFee).sub(_buybackAmt).sub(
                    _revShareAmt
                );
        }

        // Allow the router contract to spen up to earnedAmt
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _earnedAmt
        );

        // Swap Earned token to token0 if token0 is not the Earned token
        if (earnedAddress != token0Address) {
            // Get decimal info
            uint8[] memory _decimals0 = new uint8[](2);
            _decimals0[0] = ERC20Upgradeable(earnedAddress).decimals();
            _decimals0[1] = ERC20Upgradeable(token0Address).decimals();

            // Swap half earned to token0
            IAMMRouter02(uniRouterAddress).safeSwap(
                _remainingAmt.div(2),
                _priceTokens0,
                _maxMarketMovementAllowed,
                earnedToToken0Path,
                _decimals0,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Get values of tokens 0 and 1
        uint256 _token0Amt = IERC20Upgradeable(token0Address).balanceOf(
            address(this)
        );
    
        // Provided that token0 is > 0, re-deposit
        if (_token0Amt > 0) {            
            // Stake
            _liquidStake(_token0Amt);

            // Add liquidity
            uint256 _synthTokenAmt = IERC20Upgradeable(liquidStakeToken).balanceOf(address(this));
            _addLiquidity(_synthTokenAmt, _maxMarketMovementAllowed);
        }

        // Update last earned block
        lastEarnBlock = block.number;

        // Farm Want token
        _farm();
    }
}

contract VaultBenqiAVAXLiqStakeLP is VaultBenqiLiqStakeLP {}