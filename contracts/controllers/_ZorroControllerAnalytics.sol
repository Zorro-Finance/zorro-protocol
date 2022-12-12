// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerBase.sol";

import "../interfaces/Zorro/Vaults/IVault.sol";

import "../interfaces/Zorro/Controllers/IZorroController.sol";

contract ZorroControllerAnalytics is
    IZorroControllerAnalytics,
    ZorroControllerBase
{
    /* Functions */

    /// @notice View function to see pending ZORRO on frontend.
    /// @param _pid Index of pool
    /// @param _account Wallet address of on chain account
    /// @param _trancheId Tranche ID. If -1, will do pending rewards for all active tranches
    /// @return pendingRewards Amount of Zorro rewards
    function pendingZORRORewards(
        uint256 _pid,
        address _account,
        int256 _trancheId
    ) public view returns (uint256 pendingRewards) {
        // Get pool and user info
        PoolInfo storage pool = poolInfo[_pid];
        uint256 _accZORRORewards = pool.accZORRORewards;

        // Increment accumulated ZORRO rewards by the current pending Zorro rewards,
        // IF we are on a block that is greater than the previous block this function was executed in
        if (block.number > pool.lastRewardBlock) {
            uint256 elapsedBlocks = block.number - pool.lastRewardBlock;
            uint256 ZORROReward = (elapsedBlocks *
                ZORROPerBlock *
                pool.allocPoint) / totalAllocPoint;
            _accZORRORewards = _accZORRORewards + ZORROReward;
        }

        // Calculate pending rewards
        if (pool.totalTrancheContributions == 0) {
            // Return 0 if the pool has no contributions
            return 0;
        }

        // Check to see if data is needed for all tranches or a specific tranche
        if (_trancheId < 0) {
            // Get the number of tranches for this user and pool
            uint256 numTranches = trancheLength(_pid, _account);
            // Iterate through each tranche and increment rewards
            for (uint256 tid = 0; tid < numTranches; ++tid) {
                // Get the tranch
                TrancheInfo storage _tranche = trancheInfo[_pid][_account][tid];
                // Ensure tranche is not yet exited
                if (_tranche.exitedVaultAt == 0) {
                    // Return the user's share of the Zorro rewards for this pool, net of the reward debt
                    pendingRewards =
                        pendingRewards +
                        (_tranche.contribution * _accZORRORewards) /
                        pool.totalTrancheContributions -
                        _tranche.rewardDebt;
                }
            }
        } else {
            // Get tranche
            TrancheInfo storage _tranche = trancheInfo[_pid][_account][
                uint256(_trancheId)
            ];
            // Ensure tranche is not yet exited
            if (_tranche.exitedVaultAt == 0) {
                // Return the tranche's share of the Zorro rewards for this pool, net of the reward debt
                pendingRewards =
                    (_tranche.contribution * _accZORRORewards) /
                    pool.totalTrancheContributions -
                    _tranche.rewardDebt;
            } else {
                pendingRewards = 0;
            }
        }
    }

    /// @notice Shares owned by an account for a vault
    /// @param _pid Index of vault
    /// @param _account Wallet address of on chain account
    /// @param _trancheId Tranche ID, or -1 to aggregate across all tranches
    /// @return ownedShares Amount of vault shares owned (no time multipliers applied)
    function shares(
        uint256 _pid,
        address _account,
        int256 _trancheId
    ) external view returns (uint256 ownedShares) {
        // Get pool and user info
        PoolInfo storage pool = poolInfo[_pid];

        // Determine total number of shares in the underlying Zorro Vault contract
        uint256 sharesTotal = IVault(pool.vault).sharesTotal();

        // If total shares is zero, there are no staked Want tokens
        if (sharesTotal == 0) {
            return 0;
        }

        // Check to see if data is needed for all tranches or a specific tranche
        if (_trancheId < 0) {
            // Get the number of tranches for this user and pool
            uint256 numTranches = trancheLength(_pid, _account);

            // Iterate through each tranche and increment rewards
            for (uint256 tid = 0; tid < numTranches; ++tid) {
                // Get tranche
                TrancheInfo storage _tranche = trancheInfo[_pid][_account][tid];

                // Increment shares if tranche not yet exited
                if (_tranche.exitedVaultAt == 0) {
                    ownedShares +=
                        (_tranche.contribution * 1e12) /
                        _tranche.timeMultiplier;
                }
            }
        } else {
            // Get tranche
            TrancheInfo storage _tranche = trancheInfo[_pid][_account][
                uint256(_trancheId)
            ];

            // Ensure tranche is not yet exited
            if (_tranche.exitedVaultAt == 0) {
                ownedShares +=
                    (_tranche.contribution * 1e12) /
                    _tranche.timeMultiplier;
            }
        }
    }
}
