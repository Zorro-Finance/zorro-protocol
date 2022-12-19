// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_VaultLending.sol";

import "../interfaces/ApeLending/IRainMaker.sol";

/// @title Vault contract for ApeLending leveraged lending strategies
contract VaultApeLending is VaultLending {
    /* Libraries */
    
    using PriceFeed for AggregatorV3Interface;

    /* Functions */

    /// @notice Claims unclaimed rewards from lending protocols
    /// @param _amount Amount to unfarm
    function _unfarm(uint256 _amount) internal override {
        // Preflight check (unused - just here to satisfy compiler)
        require(_amount>=0);

        // Get Earn balance that has been accumulated
        uint256 _balEarn = IERC20Upgradeable(earnedAddress).balanceOf(address(this));

        // Convert earn to underlying token, if applicable
        if (_balEarn > 0) {
            IVaultActions(vaultActions).safeSwap(SafeSwapUni.SafeSwapParams({
                amountIn: _balEarn,
                priceToken0: priceFeeds[earnedAddress].getExchangeRate(),
                priceToken1: priceFeeds[token0Address].getExchangeRate(),
                token0: token0Address,
                token1: token1Address,
                maxMarketMovementAllowed: maxMarketMovementAllowed,
                path: swapPaths[earnedAddress][token0Address],
                destination: address(this)
            }));
        }

        // Withdraw appropriate amount
        _withdrawSome(_amount);
    }

    /// @notice Claim pending lending protocol rewards
    function claimLendingRewards() public override onlyAllowGov {
        // Claim any outstanding rewards
        IRainMaker(farmContractAddress).claimComp(address(this));
    }
}

contract VaultApeLendingETH is VaultApeLending {}
