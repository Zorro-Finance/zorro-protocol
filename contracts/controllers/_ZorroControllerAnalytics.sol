// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerBase.sol";

import "../interfaces/IVault.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// TODO: These don't take individual tranches into account. Do we need to? 

contract ZorroControllerAnalytics is ZorroControllerBase {
    using SafeMath for uint256;

    /// @notice View function to see pending ZORRO on frontend.
    /// @param _pid Index of pool
    /// @param _user wallet address of user
    /// @return amount of Zorro rewards
    function pendingZORRORewards(uint256 _pid, address _user) external view returns (uint256) {
        // Get pool and user info
        PoolInfo storage pool = poolInfo[_pid];
        uint256 accZORRORewards = pool.accZORRORewards;

        // Increment accumulated ZORRO rewards by the current pending Zorro rewards, 
        // IF we are on a block that is greater than the previous block this function was executed in
        if (block.number > pool.lastRewardBlock) {
            uint256 elapsedBlocks = block.number.sub(pool.lastRewardBlock);
            uint256 ZORROPerBlock = ZORROPerBlock;
            uint256 ZORROReward = elapsedBlocks.mul(ZORROPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accZORRORewards = accZORRORewards.add(ZORROReward);
        }

        // Return 0 if the pool has no contributions
        if (pool.totalTrancheContributions == 0) {
            return 0;
        }

        // Get the number of tranches for this user and pool
        uint256 numTranches = trancheLength(_pid, _user);
        uint256 pendingRewards = 0;
        // Iterate through each tranche and increment rewards
        for (uint256 tid = 0; tid < numTranches; ++tid) {
            // Get the tranch
            TrancheInfo storage tranche = trancheInfo[_pid][_user][tid];
            
            // Return the user's share of the Zorro rewards for this pool, net of the reward debt
            uint256 trancheShare = tranche.contribution.mul(1e6).div(pool.totalTrancheContributions);
            pendingRewards = pendingRewards.add(trancheShare.mul(accZORRORewards).div(1e6).sub(tranche.rewardDebt));
        }

        return pendingRewards;
    }

    /// @notice View function to see staked Want tokens on frontend.
    /// @param _pid Index of pool
    /// @param _user wallet address of user
    /// @return amount of staked Want tokens
    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256) {
        // Get pool and user info
        PoolInfo storage pool = poolInfo[_pid];

        // Determine total number of shares in the underlying Zorro Vault contract
        uint256 sharesTotal = IVault(pool.vault).sharesTotal();
        // Determine the total number of Want tokens locked into the underlying Zorro Vault contract
        uint256 wantLockedTotal = IVault(poolInfo[_pid].vault).wantLockedTotal();
        
        // If total shares is zero, there are no staked Want tokens
        if (sharesTotal == 0) {
            return 0;
        }

        // Get the number of tranches for this user and pool
        uint256 numTranches = trancheLength(_pid, _user);
        uint256 _stakedWantTokens = 0;

        // Iterate through each tranche and increment rewards
        for (uint256 tid = 0; tid < numTranches; ++tid) {
            TrancheInfo storage _tranche = trancheInfo[_pid][_user][tid];
            // Otherwise, staked Want tokens is the user's shares as a percentage of total shares multiplied by total Want tokens locked
            uint256 trancheShares = _tranche.contribution.mul(1e6).div(_tranche.timeMultiplier);
            _stakedWantTokens = _stakedWantTokens.add((trancheShares.mul(wantLockedTotal).div(1e6)).div(sharesTotal));
        }

        return _stakedWantTokens;  
    }
}
