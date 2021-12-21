// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

/* Dependencies */
import "./helpers/ERC20.sol";

import "./libraries/Address.sol";

import "./libraries/SafeERC20.sol";

import "./libraries/Math.sol";

import "./libraries/EnumerableSet.sol";

import "./helpers/Ownable.sol";

import "./helpers/ReentrancyGuard.sol";

/* Zorro ERC20 Token */
abstract contract ZorroToken is ERC20 {
    function mint(address _to, uint256 _amount) public virtual;
}

/* For interacting with our own Vaults */
interface IVault {
    // Total want tokens managed by strategy
    function wantLockedTotal() external view returns (uint256);

    // Sum of all shares of users to wantLockedTotal
    function sharesTotal() external view returns (uint256);

    // Main want token compounding function
    // Note: Earn events do not happen here. They are triggered via CRON
    function earn() external;

    // Transfer want tokens ZORROFarm -> strategy
    function deposit(address _userAddress, uint256 _wantAmt)
        external
        returns (uint256);

    // Transfer want tokens strategy -> ZORROFarm
    function withdraw(address _userAddress, uint256 _wantAmt)
        external
        returns (uint256);

    // Transfer ERC20 tokens on the Vault back to the owner, if necessary
    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) external;
}

/* Main Contract */
/// @title The main controller of the Zorro yield farming protocol. Used for cash flow operations (deposit/withdrawal), managing vaults, and rewards allocations, among other things.
contract ZorroController is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* Structs */

    // Info of each user.
    struct UserInfo {
        uint256 contribution; // The user-specific contribution for a given pool (Cx). Equivalent to the product of their contribution and a time multiplier
        uint256 timeMultiplier; // The time multiplier factor for rewards
        uint256 rewardDebt; // The user's share of the amount of rewards accumulated in the pool to date (see README)
        uint256 durationCommittedInBlocks; // How many blocks the user committed to at the time of deposit
        uint256 enteredVaultOnBlock; // The earliest contiguous block for which the user deposited into a Vault.
    }

    // Info of each pool
    struct PoolInfo {
        IERC20 want; // Address of the Want token.
        uint256 allocPoint; // How many allocation points assigned to this pool.
        uint256 lastRewardBlock; // Last block number that ZORRO distribution occurs.
        uint256 accZORRORewards; // Accumulated ZORRO rewards in this pool
        uint256 totalUserContributions; // Sum of all user contributions in this pool
        address vault; // Vault address that ZORRO compounds Want tokens upon.
    }
    // TODO: Need to account for divide by zero errors

    /* Variables */ 

    // Public variables and their initial values (check blockchain scanner for latest values)
    address public ZORRO = 0xa184088a740c695E156F91f5cC086a06bb78b827; // TODO - set this
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;
    uint256 public startBlock = 13650292; //https://bscscan.com/block/countdown/3888888 // TODO - set this
    address public publicPool = 0xa184088a740c695E156F91f5cC086a06bb78b827; // TODO - set this
    uint256 public baseRewardRateBasisPoints = 10;
    uint256 public BSCMarketTVLUSD = 30e9; // TODO - set this correctly, allow setter function
    uint256 public ZorroTotalVaultTVLUSD = 500e6; // TODO - set this correctly, allow setter function
    uint256 public targetTVLCaptureBasisPoints = 333;
    uint256 public blocksPerDay = 28800; // Approximate
    uint256 public ZORRODailyDistributionFactorBasisPointsMin = 1; // 0.01%
    uint256 public ZORRODailyDistributionFactorBasisPointsMax = 20; // 0.20%

    /* Setters */
    function setStartBlock(uint256 _blockNumber) onlyOwner {
        startBlock = _blockNumber;
    }
    function setPublicPool(address _publicPoolAddress) onlyOwner {
        publicPool = _publicPoolAddress;
    }
    function setBaseRewardRateBasisPoints(uint256 _baseRewardRateBasisPoints) onlyOwner {
        baseRewardRateBasisPoints = _baseRewardRateBasisPoints;
    }
    function setBSCMarketTVLUSD(uint256 _BSCMarketTVLUSD) onlyOwner {
        BSCMarketTVLUSD = _BSCMarketTVLUSD;
    }
    function setZorroTotalVaultTVLUSD(uint256 _ZorroTotalVaultTVLUSD) onlyOwner {
        ZorroTotalVaultTVLUSD = _ZorroTotalVaultTVLUSD;
    }
    function setTargetTVLCaptureBasisPoints(uint256 _targetTVLCaptureBasisPoints) onlyOwner {
        targetTVLCaptureBasisPoints = _targetTVLCaptureBasisPoints;
    }
    function setBlocksPerDay(uint256 _blocksPerDay) onlyOwner {
        blocksPerDay = _blocksPerDay;
    }
    function setZORRODailyDistributionFactorBasisPointsMin(uint256 _value) onlyOwner {
        ZORRODailyDistributionFactorBasisPointsMin = _value;
    }
    function setZORRODailyDistributionFactorBasisPointsMax(uint256 _value) onlyOwner {
        ZORRODailyDistributionFactorBasisPointsMax = _value;
    }


    // Info of each pool
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo; 
    // Total allocation points (aka multiplier). Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    /* Events */

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    /* View functions */

    /// @notice Number of pools in the Zorro protocol
    /// @return Number of pools
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /// @notice View function to see pending ZORRO on frontend.
    /// @param _pid Index of pool
    /// @param _user wallet address of user
    /// @return amount of Zorro rewards
    function pendingZORRORewards(uint256 _pid, address _user) external view returns (uint256) {
        // Get pool and user info
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accZORRORewards = pool.accZORRORewards;

        // Increment accumulated ZORRO rewards by the current pending Zorro rewards, 
        // IF we are on a block that is greater than the previous block this function was executed in
        if (block.number > pool.lastRewardBlock) {
            // TODO: revise calculations
            uint256 elapsedBlocks = block.number.sub(pool.lastRewardBlock);
            uint256 ZORROReward = elapsedBlocks.mul(ZORROPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accZORRORewards = accZORRORewards.add(ZORROReward);
        }

        // Determine pending Zorro rewards due to a user
         
        // Return the factor of accumulated ZORRO per share and the user's current shares, subtracted by their reward debt
        return user.shares.mul(accZORRORewards).sub(user.rewardDebt);
    }

    /// @notice View function to see staked Want tokens on frontend.
    /// @param _pid Index of pool
    /// @param _user wallet address of user
    /// @return amount of staked Want tokens
    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256) {
        // Get pool and user info
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        // TODO: Biz logic

        // Determine total number of shares in the underlying Zorro Vault contract
        uint256 sharesTotal = IVault(pool.vault).sharesTotal();
        // Determine the total number of Want tokens locked into the underlying Zorro Vault contract
        uint256 wantLockedTotal = IVault(poolInfo[_pid].vault).wantLockedTotal();
        
        // If total shares is zero, there are no staked Want tokens
        if (sharesTotal == 0) {
            return 0;
        }
        // Otherwise, staked Want tokens is the user's shares as a percentage of total shares multiplied by total Want tokens locked
        return user.shares.mul(wantLockedTotal).div(sharesTotal);
    }

    /// @notice Determine the number of Zorro to emit per block based on current market parameters
    /// @return Number of Zorro tokens per block
    function getZorroPerBlock() external view returns (uint256) {
        // Use the Rm formula to determine the percentage of the remaining public pool Zorro tokens to transfer to this contract as rewards
        uint256 ZORRODailyDistributionFactorBasisPoints = baseRewardRateBasisPoints.mul(BSCMarketTVLUSD).mul(targetTVLCaptureBasisPoints.div(10000)).div(ZorroTotalVaultTVLUSD);
        // Rail distribution to min and max values
        if (ZORRODailyDistributionFactorBasisPoints > ZORRODailyDistributionFactorBasisPointsMax) {
            ZORRODailyDistributionFactorBasisPoints = ZORRODailyDistributionFactorBasisPointsMax;
        } else if (ZORRODailyDistributionFactorBasisPoints < ZORRODailyDistributionFactorBasisPointsMin) {
            ZORRODailyDistributionFactorBasisPoints = ZORRODailyDistributionFactorBasisPointsMin;
        }
        // Find remaining token balance in the public pool
        uint256 publicPoolRemainingZORROBalance = IERC20(ZORRO).balanceOf(publicPool);
        // Multiply the factor above to determine the total Zorro tokens to distribute to this contract on a DAILY basis
        uint256 publicPoolDailyZORRODistribution = publicPoolRemainingZORROBalance.mul(ZORRODailyDistributionFactorBasisPoints).div(10000);
        // Convert this to a BLOCK basis
        return publicPoolDailyZORRODistribution.div(blocksPerDay);
    }

    /* Pool management */

    /// @notice Adds a new pool. Can only be called by the owner.
    /// @dev DO NOT add the same LP token more than once. Rewards will be messed up if you do. (Only if want tokens are stored here.)
    /// @param _allocPoint The number of allocation points for this pool (aka "multiplier")
    /// @param _want The address of the want token
    /// @param _withUpdate  Mass update all pools if set to true
    /// @param _vault The contract address of the underlying vault
    /// @return Nothing
    function add(
        uint256 _allocPoint,
        IERC20 _want,
        bool _withUpdate,
        address _vault
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
            block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                want: _want,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accZORRORewards: 0,
                totalUserContributions: 0,
                vault: _vault
            })
        );
    }

    /// @notice Update the given pool's ZORRO allocation point. Can only be called by the owner.
    /// @param _pid The index of the pool ID
    /// @param _allocPoint The number of allocation points for this pool (aka "multiplier")
    /// @param _withUpdate  Mass update all pools if set to true
    /// @return Nothing
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    /// @notice Updates reward variables of all pools
    /// @dev Be careful of gas fees!
    /// @return None
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        // Iterate through each pool and run updatePool()
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /// @notice Update reward variables of the given pool to be up-to-date.
    /// @param _pid index of pool
    /// @return None
    function updatePool(uint256 _pid) public {
        // Get the pool matching the given index
        PoolInfo storage pool = poolInfo[_pid];

        // If current block is <= last reward block, exit
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        // Determine how many blocks have elapsed since the last updatePool() operation for this pool
        uint256 elapsedBlocks = block.number.sub(pool.lastRewardBlock);
        // If no elapsed blocks have occured, exit
        if (elapsedBlocks <= 0) {
            return;
        }

        // Calculate Zorro approx. rewards per block
        uint256 ZORROPerBlock = getZorroPerBlock();
        // Finally, multiply this by the number of elapsed blocks and the pool weighting
        uint256 ZORROReward = elapsedBlocks.mul(ZORROPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        // TODO: Only issue with this is if too much time passes by without a deposit/withdrawal such that TVL and other factors change too much. Consider having a forced cron job every X blocks
        // Transfer Zorro rewards to this contract from the Public Pool
        IERC20(ZORRO).safeTransferFrom(publicPool, address(this), ZORROReward);
        // Increment this pool's accumulated Zorro per share value by the reward amount
        pool.accZORRORewards = pool.accZORRORewards.add(ZORROReward);
        // Update the pool's last reward block to the current block
        pool.lastRewardBlock = block.number;
    }

    /* Allocations */

    /// @notice Calculate time multiplier based on duration committed
    /// @param durationInWeeks number of weeks committed into Vault
    /// @return multiplier factor
    function getTimeMultiplier(uint256 durationInWeeks) private pure returns (uint256) {
        return uint256(1).add((uint256(2).div(10)).mul(sqrt(durationInWeeks)));
    }

    // TODO - careful with floating point precision (consider re-introducing 1e12 logic like Autofarm?)
    /// @notice The contribution of the user, meant to be used in rewards allocations
    /// @param _liquidityCommitted How many tokens staked (e.g. LP tokens)
    /// @param _timeMultiplier Time multiplier value (from getTimeMultiplier())
    /// @return The relative contribution of the user (unitless)
    function getUserContribution(uint256 _liquidityCommitted, uint256 _timeMultiplier) private pure returns (uint256) {
        return _liquidityCommitted.mul(_timeMultiplier);
    }

    /* Cash flow */

    /// @notice Want tokens moved from user -> ZORROFarm (ZORRO allocation) -> Strat (compounding)
    /// @param _pid index of pool
    /// @param _wantAmt how much Want tokens to deposit
    /// @param _weeksCommitted how many weeks the user is committing to on this vault
    /// @return None
    function deposit(uint256 _pid, uint256 _wantAmt, uint256 _weeksCommitted) public nonReentrant {
        // Update the pool before anything to ensure rewards have been updated and transferred
        updatePool(_pid);

        // Get pool and current user (wallet) info
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        // If the user has contributions, determine pending rewards and pay them out
        if (user.contribution > 0) {
            // Calculate the user share (their contribution divided by everyone else's contributions)
            uint256 userShare = user.contribution.div(pool.totalUserContributions);
            // Multiply the pool's accumulated rewards by the user share and subtract the "reward debt" marked at the last cash flow event
            uint256 pendingRewards = pool.accZORRORewards.mul(userShare).sub(user.rewardDebt);
            // If pending rewards exist, send them to msg.sender
            if (pendingRewards > 0) {
                safeZORROTransfer(msg.sender, pendingRewards);
            }
        }
        // If the _wantAmt is > 0, transfer Want tokens from sender to the underlying Zorro Vault contract and update shares. If NOT, user shares will NOT be updated.
        if (_wantAmt > 0) {
            // Transfer tokens from sender to this contract
            pool.want.safeTransferFrom(address(msg.sender), address(this), _wantAmt);
            // Safely allow the underlying Zorro Vault contract to transfer the Want token
            pool.want.safeIncreaseAllowance(pool.vault, _wantAmt);
            // Perform the actual deposit function on the underlying Vault contract and get the number of shares to add
            uint256 sharesAdded = IVault(poolInfo[_pid].vault).deposit(msg.sender, _wantAmt);
            // Determine the time multiplier value based on the duration committed to in weeks
            user.timeMultiplier = getTimeMultiplier(durationInWeeks);
            // Determine the individual user contribution based on the quantity of tokens to stake and the time multiplier
            uint256 contributionAdded = getUserContribution(sharesAdded, user.timeMultiplier);
            // Increment the user's contribution by the contribution added
            user.contribution = user.contribution.add(contributionAdded);
            // Increment the pool's total contributions by the contribution added
            pool.totalUserContributions = pool.totalUserContributions.add(contributionAdded);
            // If the user has not yet registered a block that it has entered on yet, assign the current block
            if (user.enteredVaultOnBlock == 0) {
                user.enteredVaultOnBlock = block.number;
            }
            // If the user has no duration committed, assign the commitment to the duration in weeks, convered to blocks
            if (user.durationCommittedInBlocks == 0) {
                user.durationCommittedInBlocks =  _weeksCommitted.mul(7).mul(blocksPerDay);
            }
        }
        // Update the reward debt that the user owes by multiplying user share % by the pool's accumulated Zorro rewards
        uint256 newUserShare = user.contribution.div(pool.totalUserContributions);
        user.rewardDebt = pool.accZORRORewards.mul(newUserShare);
        // Emit deposit event
        emit Deposit(msg.sender, _pid, _wantAmt);
    }

    /// @notice Withdraw LP tokens from MasterChef.
    /// @param _pid index of pool
    /// @param _wantAmt how much Want tokens to withdraw. If 0 is specified, function will only harvest Zorro rewards
    /// @return None
    function withdraw(uint256 _pid, uint256 _wantAmt) public nonReentrant {
        // Update the pool before anything to ensure rewards have been updated and transferred
        updatePool(_pid);

        // Get pool and current user (wallet) info
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        /* Preflight checks on contributions */
        require(user.contribution > 0, "user.contribution is 0");
        require(pool.totalUserContributions > 0, "totalUserContributions is 0");

        // Withdraw pending ZORRO rewards (a.k.a. "Harvest")
        uint256 userShare = user.contribution.div(pool.totalUserContributions);
        uint256 pendingRewards =
            userShare.mul(pool.accZORRORewards).sub(user.rewardDebt);
        if (pendingRewards > 0) {
            safeZORROTransfer(msg.sender, pendingRewards);
        }

        // Withdraw want tokens
        uint256 amount = user.contribution.div(user.timeMultiplier);
        // Establish cap for safety
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        // If the _wantAmt is > 0, transfer Want tokens from the underlying Zorro Vault contract and update shares. If NOT, user shares will NOT be updated. 
        if (_wantAmt > 0) {
            // Perform the actual withdrawal function on the underlying Vault contract and get the number of shares to remove
            uint256 sharesRemoved =
                IVault(poolInfo[_pid].vault).withdraw(msg.sender, _wantAmt);
            uint256 contributionRemoved = getUserContribution(sharesRemoved, user.timeMultiplier);
            // Update shares safely
            if (contributionRemoved > user.contribution) {
                user.contribution = 0;
                pool.totalUserContributions = pool.totalUserContributions.sub(user.contribution);
            } else {
                user.contribution = user.contribution.sub(contributionRemoved);
                pool.totalUserContributions = pool.totalUserContributions.sub(contributionRemoved);
            }
            // Withdraw Want tokens from this contract to sender
            uint256 wantBal = IERC20(pool.want).balanceOf(address(this));
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }
            pool.want.safeTransfer(address(msg.sender), _wantAmt);

            // Reset time-based rewards parameters if everything is withdrawn
            if (user.contribution == 0) {
                user.durationCommittedInBlocks = 0;
                user.enteredVaultOnBlock = 0;
            }
        }
        // Note: User's reward debt is issued on every deposit/withdrawal so that we don't count the full pool accumulation of ZORRO rewards.
        uint256 newUserShare = user.contribution.div(pool.totalUserContributions);
        user.rewardDebt = pool.accZORRORewards.mul(newUserShare);
        emit Withdraw(msg.sender, _pid, _wantAmt);
    }

    /// @notice Withdraw the maximum number of Want tokens from a pool
    /// @param _pid index of pool
    /// @return None
    function withdrawAll(uint256 _pid) public nonReentrant {
        // uint256(-1) == 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF (i.e. the max amount possible)
        withdraw(_pid, uint256(-1));
    }

    /* Emergency functions */

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param _pid index of pool
    /// @return None
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        // Get pool and user info
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        // Determine the total quantity of Want tokens locked in the underlying Zorro Vault contract
        uint256 wantLockedTotal =
            IVault(poolInfo[_pid].vault).wantLockedTotal();
        // Determine total number of shares in the underlying Zorro Vault contract
        uint256 sharesTotal = IVault(poolInfo[_pid].vault).sharesTotal();
        // Determine amount to withdraw by multiplying user's shares (as a percentage of total shares) against the total Want tokens locked
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);

        // Call withdraw() function of underlying Zorro vault contract
        IVault(poolInfo[_pid].vault).withdraw(msg.sender, amount);
        // Safely transfer amount back to caller
        pool.want.safeTransfer(address(msg.sender), amount);
        // Emit EmergencyWithdraw event
        emit EmergencyWithdraw(msg.sender, _pid, amount);
        // Finally, force set the user shares and reward debt to zero, respectively.
        user.shares = 0;
        user.rewardDebt = 0;
    }

    /// @notice Safe ZORRO transfer function, just in case if rounding error causes pool to not have enough
    /// @param _to destination for funds
    /// @param _ZORROAmt quantity of Zorro tokens to send
    /// @return None
    function safeZORROTransfer(address _to, uint256 _ZORROAmt) internal {
        uint256 ZORROBal = IERC20(ZORRO).balanceOf(address(this));
        if (_ZORROAmt > ZORROBal) {
            IERC20(ZORRO).transfer(_to, ZORROBal);
        } else {
            IERC20(ZORRO).transfer(_to, _ZORROAmt);
        }
    }

    /// @notice For owner to recover ERC20 tokens on this contract if stuck
    /// @dev Does not permit usage for the Zorro token
    /// @param _token ERC20 token address
    /// @param _amount token quantity
    /// @return None
    function inCaseTokensGetStuck(address _token, uint256 _amount)
        public
        onlyOwner
    {
        require(_token != ZORRO, "!safe to use Zorro token in func inCaseTokensGetStuck");
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }
}

// TODO - how do penalties work?
// TODO harvesting before time commitment period should incur a penalty if it's an early harvest

// TODO: Instead of using duration in weeks converted to blocks: Use block.timestamp https://ethereum.stackexchange.com/questions/37026/how-to-calculate-with-time-and-dates

// TODO - how to gradually allow room for Oracle controlled TVL etc?

// TODO: be careful about floating point percentage

// TODO: Deposit: Autoswapping
// TODO: Withdrawal: Back to USDC