// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IAMMFarm.sol";

import "../interfaces/Zorro/Vaults/IVaultLiqStakeLP.sol";

import "./actions/_VaultActionsLiqStakeLP.sol";

import "./_VaultBase.sol";

/// @title Vault base contract for liquid staking + LP strategy
contract VaultBaseLiqStakeLP is IVaultLiqStakeLP, VaultBase {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */

    /// @notice Upgradeable constructor
    /// @param _initValue A VaultAlpacaInit struct containing all init values
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultBaseLiqStakeLPInit memory _initValue
    ) public initializer {
        // Addresses
        liquidStakeToken = _initValue.liquidStakeToken;
        liquidStakingPool = _initValue.liquidStakingPool;

        // Swap paths
        _setSwapPaths(_initValue.liquidStakeToToken0Path);
        _setSwapPaths(
            VaultActions(vaultActions).reversePath(
                _initValue.liquidStakeToToken0Path
            )
        );

        // Price feeds
        _setPriceFeed(
            liquidStakeToken,
            _initValue.liquidStakeTokenPriceFeed
        );

        // Super call
        VaultBase.initialize(_timelockOwner, _initValue.baseInit);
    }

    /* State */

    address public liquidStakeToken; // Synth token for liquid staking (e.g. sETH)
    address public liquidStakingPool; // Liquid staking pool (can sometimes be the same as liquidStakeToken)
    AggregatorV3Interface public liquidStakeTokenPriceFeed; // Price feed for sETH

    /* Investment Actions */

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming LP token. Responsible for staking LP token in a MasterChef/MasterApe-like contract
    function _farm() internal override {
        // Calc balance of sETH on this contract
        uint256 _synthBal = IERC20Upgradeable(liquidStakeToken).balanceOf(
            address(this)
        );

        // Approve spending
        IERC20Upgradeable(liquidStakeToken).safeIncreaseAllowance(
            vaultActions,
            _synthBal
        );

        // Swap 1/2 sETH, to ETH and add liquidity to an LP Pool (sends LP token back to this address)
        VaultActionsLiqStakeLP(vaultActions).stakeInLPPool(
            _synthBal,
            VaultActionsLiqStakeLP.StakeLiqTokenInLPPoolParams({
                liquidStakeToken: liquidStakeToken,
                nativeToken: token0Address,
                liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                nativeTokenPriceFeed: priceFeeds[token0Address],
                liquidStakeToNativePath: swapPaths[liquidStakeToken][
                    token0Address
                ]
            }),
            maxMarketMovementAllowed
        );

        // Get the LP token stored on this contract
        uint256 _lpBal = IERC20Upgradeable(poolAddress).balanceOf(
            address(this)
        );

        // Allow the farm contract (e.g. MasterChef/MasterApe) the ability to transfer up to the Want amount
        IERC20Upgradeable(poolAddress).safeIncreaseAllowance(
            farmContractAddress,
            _lpBal
        );

        // Deposit the Want tokens in the Farm contract for the appropriate pool ID (PID) IF AMM Masterchef allocates rewards
        if (isFarmable) {
            IAMMFarm(farmContractAddress).deposit(pid, _lpBal);
        }
    }

    /// @notice Internal function for unfarming LP token. Responsible for unstaking LP token from MasterChef/MasterApe contracts
    /// @param _lpAmt the amount of LP tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _lpAmt) internal override {
        // Withdraw the LP tokens from the Farm contract pool (IF AMM Masterchef allocates rewards)
        if (isFarmable) {
            IAMMFarm(farmContractAddress).withdraw(pid, _lpAmt);
        }

        // Calc balance
        uint256 _balLPToken = IERC20Upgradeable(poolAddress).balanceOf(
            address(this)
        );

        // Approve spending
        IERC20Upgradeable(poolAddress).safeIncreaseAllowance(
            vaultActions,
            _balLPToken
        );

        // Convert LP tokens to sETH + ETH and swap to sETH (want token), deliver back to this contract
        VaultActionsLiqStakeLP(vaultActions).unStakeFromLPPool(
            _balLPToken,
            VaultActionsLiqStakeLP.UnstakeLiqTokenFromLPPoolParams({
                liquidStakeToken: liquidStakeToken,
                nativeToken: token0Address,
                lpPoolToken: poolAddress,
                liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                nativeTokenPriceFeed: priceFeeds[token0Address],
                nativeToLiquidStakePath: swapPaths[token0Address][
                    liquidStakeToken
                ]
            }),
            maxMarketMovementAllowed
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
            VaultActionsLiqStakeLP(vaultActions).exchangeUSDForWantToken(
                _amountUSD,
                VaultActionsLiqStakeLP.ExchangeUSDForWantParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    liquidStakeToken: liquidStakeToken,
                    liquidStakePool: liquidStakingPool,
                    poolAddress: poolAddress,
                    token0PriceFeed: priceFeeds[token0Address],
                    liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                    stablecoinPriceFeed: priceFeeds[defaultStablecoin],
                    stablecoinToToken0Path: swapPaths[defaultStablecoin][
                        token0Address
                    ],
                    liquidStakeToToken0Path: swapPaths[liquidStakeToken][
                        token0Address
                    ]
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
            VaultActionsLiqStakeLP(vaultActions).exchangeWantTokenForUSD(
                _amount,
                VaultActionsLiqStakeLP.ExchangeWantTokenForUSDParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    poolAddress: poolAddress,
                    liquidStakeToken: liquidStakeToken,
                    token0PriceFeed: priceFeeds[token0Address],
                    liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                    stablecoinPriceFeed: priceFeeds[defaultStablecoin],
                    liquidStakeToToken0Path: swapPaths[liquidStakeToken][
                        token0Address
                    ],
                    token0ToStablecoinPath: swapPaths[token0Address][
                        defaultStablecoin
                    ]
                }),
                _maxMarketMovementAllowed
            );
    }
}

contract VaultAnkrBNBLiqStakeLP is VaultBaseLiqStakeLP {}

contract VaultBenqiAVAXLiqStakeLP is VaultBaseLiqStakeLP {}
