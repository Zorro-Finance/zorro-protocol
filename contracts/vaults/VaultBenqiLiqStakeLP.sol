// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_VaultBaseLiqStakeLP.sol";

import "./actions/VaultActionsBenqiLiqStakeLP.sol";

/// @title Vault contract for Benqi liquid staking + LP strategy
contract VaultBenqiLiqStakeLP is VaultBaseLiqStakeLP {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;
    using SafeMathUpgradeable for uint256;
    using SafeSwapUni for IAMMRouter02;

    /* Functions */

    /// @notice Deposits liquid stake on Benqi protocol
    /// @param _amount The amount of AVAX to liquid stake
    function _liquidStake(uint256 _amount) internal override whenNotPaused {
        // Allow spending
        IERC20Upgradeable(token0Address).safeIncreaseAllowance(
            vaultActions,
            _amount
        );

        // Stake
        VaultActionsBenqiLiqStakeLP(vaultActions).liquidStake(
            _amount,
            token0Address,
            liquidStakeToken,
            liquidStakingPool
        );
    }

    /// @notice Withdraws liquid stake on Benqi protocol
    /// @param _amount The amount of AVAX to unstake
    function _liquidUnstake(uint256 _amount) internal override whenNotPaused {
        VaultActionsBenqiLiqStakeLP(vaultActions).liquidUnstake(
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

    /// @notice Performs necessary operations to convert USD into Want token
    /// @param _amountUSD The USD quantity to exchange (must already be deposited)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        // Increase allowance
        IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(
            vaultActions,
            _amountUSD
        );

        // Exchange
        return
            VaultActionsBenqiLiqStakeLP(vaultActions).exchangeUSDForWantToken(
                _amountUSD,
                VaultActionsLiqStakeLP.ExchangeUSDForWantParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    liquidStakeToken: liquidStakeToken,
                    liquidStakePool: liquidStakingPool,
                    poolAddress: poolAddress,
                    wantAddress: wantAddress,
                    token0PriceFeed: token0PriceFeed,
                    liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                    stablecoinPriceFeed: stablecoinPriceFeed,
                    stablecoinToToken0Path: stablecoinToToken0Path,
                    liquidStakeToToken0Path: liquidStakeToToken0Path
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
        // Allow spending
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            vaultActions,
            _amount
        );

        // Spending
        return
            VaultActionsBenqiLiqStakeLP(vaultActions).exchangeWantTokenForUSD(
                _amount,
                VaultActionsLiqStakeLP.ExchangeWantTokenForUSDParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    wantAddress: wantAddress,
                    poolAddress: poolAddress,
                    liquidStakeToken: liquidStakeToken,
                    token0PriceFeed: token0PriceFeed,
                    liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                    stablecoinPriceFeed: stablecoinPriceFeed,
                    liquidStakeToToken0Path: liquidStakeToToken0Path,
                    token0ToStablecoinPath: token0ToStablecoinPath
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
        uint256 _earnedAmt = IERC20Upgradeable(earnedAddress).balanceOf(
            address(this)
        );

        // Require pending rewards in order to continue
        require(_earnedAmt > 0, "0earn");

        // Create rates struct
        VaultActions.ExchangeRates memory _rates = VaultActions.ExchangeRates({
            earn: earnTokenPriceFeed.getExchangeRate(),
            ZOR: ZORPriceFeed.getExchangeRate(),
            lpPoolOtherToken: lpPoolOtherTokenPriceFeed.getExchangeRate(),
            stablecoin: stablecoinPriceFeed.getExchangeRate()
        });

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

        // Swap Earned token to token0 if token0 is not the Earned token
        if (earnedAddress != token0Address) {
            // Allow spending
            IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
                vaultActions,
                _remainingAmt
            );

            // Swap earned to token0
            VaultActionsBenqiLiqStakeLP(vaultActions).safeSwap(
                SafeSwapParams({
                    amountIn: _remainingAmt,
                    priceToken0: _rates.earn,
                    priceToken1: token0PriceFeed.getExchangeRate(),
                    token0: earnedAddress,
                    token1: token0Address,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: earnedToToken0Path,
                    destination: address(this)
                })
            );
        }

        // Get values of tokens 0 and 1
        uint256 _token0Bal = IERC20Upgradeable(token0Address).balanceOf(
            address(this)
        );

        // Provided that token0 is > 0, re-deposit
        if (_token0Bal > 0) {
            // Stake
            _liquidStake(_token0Bal);

            // Calc synth token balance
            uint256 _synthTokenBal = IERC20Upgradeable(liquidStakeToken)
                .balanceOf(address(this));

            // Approve spending
            IERC20Upgradeable(liquidStakeToken).safeIncreaseAllowance(
                vaultActions,
                _synthTokenBal.div(2)
            );

            // Swap 1/2 sETH to ETH
            VaultActionsBenqiLiqStakeLP(vaultActions).safeSwap(
                SafeSwapParams({
                    amountIn: _synthTokenBal.div(2),
                    priceToken0: liquidStakeTokenPriceFeed.getExchangeRate(),
                    priceToken1: token0PriceFeed.getExchangeRate(),
                    token0: liquidStakeToken,
                    token1: token0Address,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: liquidStakeToToken0Path,
                    destination: address(this)
                })
            );

            // Re-calc balances
            _synthTokenBal = IERC20Upgradeable(liquidStakeToken).balanceOf(
                address(this)
            );
            _token0Bal = IERC20Upgradeable(token0Address).balanceOf(
                address(this)
            );

            // Approve spending
            IERC20Upgradeable(liquidStakeToken).safeIncreaseAllowance(
                vaultActions,
                _synthTokenBal
            );
            IERC20Upgradeable(token0Address).safeIncreaseAllowance(
                vaultActions,
                _token0Bal
            );

            // Add liquidity back
            VaultActionsBenqiLiqStakeLP(vaultActions).joinPool(
                liquidStakeToken,
                token0Address,
                _synthTokenBal,
                _token0Bal,
                _maxMarketMovementAllowed,
                address(this)
            );
        }

        // Update last earned block
        lastEarnBlock = block.number;

        // Farm Want token
        _farm();
    }
}

contract VaultBenqiAVAXLiqStakeLP is VaultBenqiLiqStakeLP {}
