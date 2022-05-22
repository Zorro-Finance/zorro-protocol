// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerBase.sol";

import "../interfaces/IVault.sol";

import "../interfaces/IZorroController.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

contract ZorroControllerAnalytics is
    IZorroControllerAnalytics,
    ZorroControllerBase
{
    using SafeMathUpgradeable for uint256;

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
            uint256 elapsedBlocks = block.number.sub(pool.lastRewardBlock);
            uint256 ZORROReward = elapsedBlocks
                .mul(ZORROPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            _accZORRORewards = _accZORRORewards.add(ZORROReward);
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
                    pendingRewards = pendingRewards.add(
                        _tranche
                            .contribution
                            .mul(_accZORRORewards)
                            .div(pool.totalTrancheContributions)
                            .sub(_tranche.rewardDebt)
                    );
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
                pendingRewards = (
                    _tranche.contribution.mul(_accZORRORewards).div(
                        pool.totalTrancheContributions
                    )
                ).sub(_tranche.rewardDebt);
            } else {
                pendingRewards = 0;
            }
        }
    }

    /// @notice View function to see staked Want tokens on frontend.
    /// @param _pid Index of pool
    /// @param _account Wallet address of on chain account
    /// @param _trancheId Tranche ID, or -1 to aggregate across all tranches
    /// @return stakedWantAmt Amount of staked Want tokens
    function stakedWantTokens(
        uint256 _pid,
        address _account,
        int256 _trancheId
    ) external view returns (uint256 stakedWantAmt) {
        // Get pool and user info
        PoolInfo storage pool = poolInfo[_pid];
        // Determine total number of shares in the underlying Zorro Vault contract
        uint256 sharesTotal = IVault(pool.vault).sharesTotal();
        // Determine the total number of Want tokens locked into the underlying Zorro Vault contract
        uint256 wantLockedTotal = IVault(pool.vault).wantLockedTotal();

        // If total shares is zero, there are no staked Want tokens
        if (sharesTotal == 0) {
            stakedWantAmt = 0;
        }

        // Check to see if data is needed for all tranches or a specific tranche
        if (_trancheId < 0) {
            // Get the number of tranches for this user and pool
            uint256 numTranches = trancheLength(_pid, _account);

            // Iterate through each tranche and increment rewards
            for (uint256 tid = 0; tid < numTranches; ++tid) {
                TrancheInfo storage _tranche = trancheInfo[_pid][_account][tid];
                // Otherwise, staked Want tokens is the user's shares as a percentage of total shares multiplied by total Want tokens locked
                stakedWantAmt = stakedWantAmt.add(
                    _tranche.contribution.mul(wantLockedTotal).div(
                        sharesTotal.mul(_tranche.timeMultiplier)
                    )
                );
            }
        } else {
            // Get tranche
            TrancheInfo storage _tranche = trancheInfo[_pid][_account][
                uint256(_trancheId)
            ];
            // Ensure tranche is not yet exited
            if (_tranche.exitedVaultAt == 0) {
                // Otherwise, staked Want tokens is the tranche's shares as a percentage of total shares multiplied by total Want tokens locked
                stakedWantAmt = stakedWantAmt.add(
                    _tranche.contribution.mul(wantLockedTotal).div(
                        sharesTotal.mul(_tranche.timeMultiplier)
                    )
                );
            } else {
                stakedWantAmt = 0;
            }
        }
    }
}
