// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ZorroControllerBase.sol";

import "./libraries/SafeMath.sol";

contract ZorroControllerPoolMgmt is ZorroControllerBase {
    using SafeMath for uint256;
    
    /* Pool management */

    /// @notice Adds a new pool. Can only be called by the owner.
    /// @dev DO NOT add the same Want token more than once. Rewards will be messed up if you do. (Only if Want tokens are stored here.)
    /// @param _allocPoint The number of allocation points for this pool (aka "multiplier")
    /// @param _want The address of the want token
    /// @param _withUpdate  Mass update all pools if set to true
    /// @param _vault The contract address of the underlying vault
    /// @param _intermediaryToken The address of an intermediary token (i.e. what is returned back to the user upon withdrawal) or 0 (only applicable for protocols like Tranchess)
    function add(
        uint256 _allocPoint,
        IERC20 _want,
        bool _withUpdate,
        address _vault,
        address _intermediaryToken
    ) public onlyOwner {
        // If _withUpdate provided, update all pools
        if (_withUpdate) {
            massUpdatePools();
        }
        // Last reward block set to current block, or the start block if the startBlock hasn't been provided
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        // Increment the total allocation points by the provided _allocPoint
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        // Push to the poolInfo array
        poolInfo.push(
            PoolInfo({
                want: _want,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accZORRORewards: 0,
                totalTrancheContributions: 0,
                vault: _vault,
                intermediaryToken: _intermediaryToken
            })
        );
    }

    /// @notice Update the given pool's ZORRO allocation point. Can only be called by the owner.
    /// @param _pid The index of the pool ID
    /// @param _allocPoint The number of allocation points for this pool (aka "multiplier")
    /// @param _withUpdate  Mass update all pools if set to true
    /// @param _intermediaryToken The address of an intermediary token (i.e. what is returned back to the user upon withdrawal) or 0 (only applicable for protocols like Tranchess)
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate, 
        address _intermediaryToken
    ) public onlyOwner {
        // If _withUpdate provided, update all pools
        if (_withUpdate) {
            massUpdatePools();
        }
        // Adjust the total allocation points by the provided _allocPoint
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        // Update the key params for this pool
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].intermediaryToken = _intermediaryToken;
    }

    /// @notice Updates reward variables of all pools
    /// @dev Be careful of gas fees!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        // Iterate through each pool and run updatePool()
        for (uint256 pid = 0; pid < length; ++pid) {
            this.updatePool(pid);
        }
    }
}
