// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/* Dependencies */
import "./helpers/ERC20.sol";

import "./libraries/SafeERC20.sol";

import "./libraries/Math.sol";

import "./libraries/SafeMath.sol";

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
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* Structs */

    // Info of each tranche.
    struct TrancheInfo {
        uint256 contribution; // The tranche-specific contribution for a given pool (Cx). Equivalent to the product of their contribution and a time multiplier
        uint256 timeMultiplier; // The time multiplier factor for rewards
        uint256 rewardDebt; // The tranche's share of the amount of rewards accumulated in the pool to date (see README)
        uint256 durationCommittedInWeeks; // How many weeks the user committed to at the time of deposit for this tranche
        uint256 enteredVaultAt; // The earliest timestamp for which the user deposited into a Vault.
    }

    // Info of each pool
    struct PoolInfo {
        IERC20 want; // Address of the Want token.
        uint256 allocPoint; // How many allocation points assigned to this pool.
        uint256 lastRewardBlock; // Last block number that ZORRO distribution occurs.
        uint256 accZORRORewards; // Accumulated ZORRO rewards in this pool
        uint256 totalTrancheContributions; // Sum of all user contributions in this pool
        address vault; // Vault address that ZORRO compounds Want tokens upon.
        address lib; // Address of deployed library for this pool
    }

    /* Variables */ 

    // Public variables and their initial values (check blockchain scanner for latest values)
    address public ZORRO = 0xa184088a740c695E156F91f5cC086a06bb78b827; // TODO - set this
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;
    uint256 public startBlock = 13650292; //https://bscscan.com/block/countdown/13650292 // TODO - set this
    // TODO - be careful about how startblock should be used
    address public publicPool = 0xa184088a740c695E156F91f5cC086a06bb78b827; // TODO - set this
    uint256 public baseRewardRateBasisPoints = 10;
    uint256 public BSCMarketTVLUSD = 30e9; // TODO - set this correctly, allow setter function
    uint256 public ZorroTotalVaultTVLUSD = 500e6; // TODO - set this correctly, allow setter function
    uint256 public targetTVLCaptureBasisPoints = 333;
    uint256 public blocksPerDay = 28800; // Approximate
    uint256 public ZORRODailyDistributionFactorBasisPointsMin = 1; // 0.01%
    uint256 public ZORRODailyDistributionFactorBasisPointsMax = 20; // 0.20%
    bool public isTimeMultiplierActive = true; // If true, allows use of time multiplier
    address public defaultStablecoin = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d; // USDC

    /* Setters */
    function setStartBlock(uint256 _blockNumber) external onlyOwner {
        startBlock = _blockNumber;
    }
    function setPublicPool(address _publicPoolAddress) external onlyOwner {
        publicPool = _publicPoolAddress;
    }
    function setBaseRewardRateBasisPoints(uint256 _baseRewardRateBasisPoints) external onlyOwner {
        baseRewardRateBasisPoints = _baseRewardRateBasisPoints;
    }
    function setBSCMarketTVLUSD(uint256 _BSCMarketTVLUSD) external onlyOwner {
        BSCMarketTVLUSD = _BSCMarketTVLUSD;
    }
    function setZorroTotalVaultTVLUSD(uint256 _ZorroTotalVaultTVLUSD) external onlyOwner {
        ZorroTotalVaultTVLUSD = _ZorroTotalVaultTVLUSD;
    }
    function setTargetTVLCaptureBasisPoints(uint256 _targetTVLCaptureBasisPoints) external onlyOwner {
        targetTVLCaptureBasisPoints = _targetTVLCaptureBasisPoints;
    }
    function setBlocksPerDay(uint256 _blocksPerDay) external onlyOwner {
        blocksPerDay = _blocksPerDay;
    }
    function setZORRODailyDistributionFactorBasisPointsMin(uint256 _value) external onlyOwner {
        ZORRODailyDistributionFactorBasisPointsMin = _value;
    }
    function setZORRODailyDistributionFactorBasisPointsMax(uint256 _value) external onlyOwner {
        ZORRODailyDistributionFactorBasisPointsMax = _value;
    }
    function setIsTimeMultiplierActive(bool _isActive) external onlyOwner {
        isTimeMultiplierActive = _isActive;
    }


    // Info of each pool
    PoolInfo[] public poolInfo;
    // List of active tranches that stakes Want tokens. Mapping: pool ID/index => user wallet address => list of tranches
    mapping(uint256 => mapping(address => TrancheInfo[])) public trancheInfo; 
    // Total allocation points (aka multiplier). Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    /* Events */

    event Deposit(address indexed user, uint256 indexed pid, uint256 wantAmount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 trancheId, uint256 wantAmount);
    event TransferInvestment(address user, uint256 indexed fromPid, uint256 indexed fromTrancheId, uint256 indexed toPid);

    /* View functions */

    /// @notice Number of pools in the Zorro protocol
    /// @return Number of pools
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /// @notice Number of tranches invested by a given user into a given pool
    /// @param _pid Index of pool
    /// @param _user wallet address of user
    /// @return Number of tranches
    function trancheLength(uint256 _pid, address _user) public view returns (uint256) {
        return trancheInfo[_pid][_user].length;
    }

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
            uint256 ZORROPerBlock = getZorroPerBlock();
            uint256 ZORROReward = elapsedBlocks.mul(ZORROPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accZORRORewards = accZORRORewards.add(ZORROReward);
        }

        if (pool.totalTrancheContributions == 0) {
            return 0;
        }

        uint256 numTranches = trancheLength(_pid, _user);
        uint256 pendingRewards = 0;
        // Iterate through each tranche and increment rewards
        for (uint256 tid = 0; tid < numTranches; ++tid) {
            TrancheInfo storage tranche = trancheInfo[_pid][_user][tid];
            
            // Return the user's share of the Zorro rewards for this pool net of the reward debt
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

    /// @notice Determine the number of Zorro to emit per block based on current market parameters
    /// @return Number of Zorro tokens per block
    function getZorroPerBlock() public view returns (uint256) {
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
    /// @param _lib The address of the deployed library for this pool
    function add(
        uint256 _allocPoint,
        IERC20 _want,
        bool _withUpdate,
        address _vault,
        address _lib
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
                totalTrancheContributions: 0,
                vault: _vault,
                lib: _lib
            })
        );
    }

    /// @notice Update the given pool's ZORRO allocation point. Can only be called by the owner.
    /// @param _pid The index of the pool ID
    /// @param _allocPoint The number of allocation points for this pool (aka "multiplier")
    /// @param _withUpdate  Mass update all pools if set to true
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
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        // Iterate through each pool and run updatePool()
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /// @notice Update reward variables of the given pool to be up-to-date.
    /// @param _pid index of pool
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
    /// @return multiplier factor, times 1e12
    function getTimeMultiplier(uint256 durationInWeeks) private view returns (uint256) {
        if (isTimeMultiplierActive) {
            return (uint256(1).add((uint256(2).div(10)).mul(durationInWeeks.sqrt()))).mul(1e12);
        } else {
            return 1e12;
        }
    }

    /// @notice The contribution of the user, meant to be used in rewards allocations
    /// @param _liquidityCommitted How many tokens staked (e.g. LP tokens)
    /// @param _timeMultiplier Time multiplier value (from getTimeMultiplier())
    /// @return The relative contribution of the user (unitless)
    function getUserContribution(uint256 _liquidityCommitted, uint256 _timeMultiplier) private pure returns (uint256) {
        return _liquidityCommitted.mul(_timeMultiplier).div(1e12);
    }

    /* Cash flow */

    /// @notice Want tokens moved from user -> ZORROFarm (ZORRO allocation) -> Strat (compounding)
    /// @param _pid index of pool
    /// @param _wantAmt how much Want token to deposit
    /// @param _weeksCommitted how many weeks the user is committing to on this vault
    function deposit(uint256 _pid, uint256 _wantAmt, uint256 _weeksCommitted) public nonReentrant {
        _deposit(_pid, _wantAmt, _weeksCommitted, block.timestamp);
    }

    /// @notice Internal function for depositing wantTokens into Vault
    /// @dev Because the vault entry date can be backdated, this is a dangerous method and should only be called indirectly through other functions
    /// @param _pid index of pool
    /// @param _wantAmt how much Want token to deposit
    /// @param _weeksCommitted how many weeks the user is committing to on this vault
    /// @param _enteredVaultAt Date to backdate vault entry to
    function _deposit(uint256 _pid, uint256 _wantAmt, uint256 _weeksCommitted, uint256 _enteredVaultAt) internal {
        // Preflight checks
        require(_wantAmt > 0, "_wantAmt must be > 0!");

        // Update the pool before anything to ensure rewards have been updated and transferred
        updatePool(_pid);

        // Get pool info
        PoolInfo storage pool = poolInfo[_pid];

        // Safely allow the underlying Zorro Vault contract to transfer the Want token
        pool.want.safeIncreaseAllowance(pool.vault, _wantAmt);
        // Perform the actual deposit function on the underlying Vault contract and get the number of shares to add
        uint256 sharesAdded = IVault(poolInfo[_pid].vault).deposit(msg.sender, _wantAmt);
        // Determine the time multiplier value based on the duration committed to in weeks
        uint256 timeMultiplier = getTimeMultiplier(_weeksCommitted);
        // Determine the individual user contribution based on the quantity of tokens to stake and the time multiplier
        uint256 contributionAdded = getUserContribution(sharesAdded, timeMultiplier);
        // Increment the pool's total contributions by the contribution added
        pool.totalTrancheContributions = pool.totalTrancheContributions.add(contributionAdded);
        // Update the reward debt that the user owes by multiplying user share % by the pool's accumulated Zorro rewards
        uint256 newTrancheShare = contributionAdded.mul(1e12).div(pool.totalTrancheContributions);
        uint256 rewardDebt = pool.accZORRORewards.mul(newTrancheShare).div(1e12);
        // Push a new tranche for this user
        trancheInfo[_pid][msg.sender].push(TrancheInfo({
            contribution: contributionAdded,
            timeMultiplier: timeMultiplier,
            durationCommittedInWeeks: _weeksCommitted,
            enteredVaultAt: _enteredVaultAt,
            rewardDebt: rewardDebt
        }));
        // Emit deposit event
        emit Deposit(msg.sender, _pid, _wantAmt);
    }

    /// @notice Deposits funds in a full service manner (performs autoswaps and obtains Want tokens)
    /// @param _pid index of pool to deposit into
    /// @param _valueUSDC value in USDC (in ether units) to deposit
    /// @param _sourceTokens list of tokens to autoswap from 
    /// @param _weeksCommitted how many weeks to commit to the Pool (can be 0 or any uint)
    function depositFullService(uint256 _pid, uint256 _valueUSDC, address[] memory _sourceTokens, uint256 _weeksCommitted) public nonReentrant {
        _depositFullService(_pid, _valueUSDC, _sourceTokens, _weeksCommitted, block.timestamp);
    }

    /// @notice Private function for depositing
    /// @dev Dangerous method, as vaultEnteredAt can be backdated
    /// @param _pid index of pool to deposit into
    /// @param _valueUSDC value in USDC (in ether units) to deposit
    /// @param _sourceTokens list of tokens to autoswap from 
    /// @param _weeksCommitted how many weeks to commit to the Pool (can be 0 or any uint)
    /// @param _vaultEnteredAt date that the vault was entered at
    function _depositFullService(uint256 _pid, uint256 _valueUSDC, address[] memory _sourceTokens, uint256 _weeksCommitted, uint256 _vaultEnteredAt) internal {
        // Get library from pool
        address lib = poolInfo[_pid].lib;
        // Perform delegate call to autoswap and receive tokens and enter underlying vaults
        (bool success, bytes memory data) = lib.delegatecall(abi.encodeWithSignature("deposit(uint256, address[], uint256)", _valueUSDC, _sourceTokens));
        require(success, "delegatecall to deposit() failed");
        uint256 wantAmt = abi.decode(data, (uint256));
        // Call core deposit function
        _deposit(_pid, wantAmt, _weeksCommitted, _vaultEnteredAt);
    }

    /// @notice Withdraw LP tokens from MasterChef.
    /// @param _pid index of pool
    /// @param _trancheId index of tranche
    /// @param _wantAmt how much Want token to withdraw. If 0 is specified, function will only harvest Zorro rewards and not actually withdraw
    /// @return Amount of Want token withdrawn
    function withdraw(uint256 _pid, uint256 _trancheId, uint256 _wantAmt) public nonReentrant returns (uint256) {
        // Update the pool before anything to ensure rewards have been updated and transferred
        updatePool(_pid);

        // Get pool and current tranche info
        PoolInfo storage pool = poolInfo[_pid];
        TrancheInfo storage tranche = trancheInfo[_pid][msg.sender][_trancheId];

        /* Preflight checks on contributions */
        require(tranche.contribution > 0, "tranche.contribution is 0");
        require(pool.totalTrancheContributions > 0, "totalTrancheContributions is 0");

        // Withdraw pending ZORRO rewards (a.k.a. "Harvest")
        uint256 trancheShare = tranche.contribution.mul(1e12).div(pool.totalTrancheContributions);
        uint256 pendingRewards = trancheShare.mul(pool.accZORRORewards).div(1e12).sub(tranche.rewardDebt);
        if (pendingRewards > 0) {
            // Check if this is an early withdrawal
            // If so, slash the accumulated rewards proportionally to the % time remaining before maturity of the time commitment
            // If not, distribute rewards as normal
            uint256 oneWeek = 1 weeks;
            uint256 timeRemainingInCommitment = tranche.enteredVaultAt.add(tranche.durationCommittedInWeeks.mul(oneWeek)).sub(block.timestamp);
            uint256 rewardsDue = 0;
            if (timeRemainingInCommitment > 0) {
                rewardsDue = pendingRewards.sub(pendingRewards.mul(timeRemainingInCommitment).div(tranche.durationCommittedInWeeks.mul(oneWeek)));
            } else {
                rewardsDue = pendingRewards;
            }
            safeZORROTransfer(msg.sender, rewardsDue);
        }

        // Get current amount in tranche
        uint256 amount = tranche.contribution.mul(1e12).div(tranche.timeMultiplier);
        // Establish cap for safety
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        // If the _wantAmt is > 0, transfer Want tokens from the underlying Zorro Vault contract and update shares. If NOT, user shares will NOT be updated. 
        if (_wantAmt > 0) {
            // Perform the actual withdrawal function on the underlying Vault contract and get the number of shares to remove
            uint256 sharesRemoved = IVault(poolInfo[_pid].vault).withdraw(msg.sender, _wantAmt);
            uint256 contributionRemoved = getUserContribution(sharesRemoved, tranche.timeMultiplier);
            // Update shares safely
            if (contributionRemoved > tranche.contribution) {
                tranche.contribution = 0;
                pool.totalTrancheContributions = pool.totalTrancheContributions.sub(tranche.contribution);
            } else {
                tranche.contribution = tranche.contribution.sub(contributionRemoved);
                pool.totalTrancheContributions = pool.totalTrancheContributions.sub(contributionRemoved);
            }
            // Withdraw Want tokens from this contract to sender
            uint256 wantBal = IERC20(pool.want).balanceOf(address(this));
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }
            pool.want.safeTransfer(address(msg.sender), _wantAmt);

            // Remove tranche from this user if it's a full withdrawal
            if (_wantAmt == amount) {
                uint256 _trancheLength = trancheLength(_pid, msg.sender);
                trancheInfo[_pid][msg.sender][_trancheId] = trancheInfo[_pid][msg.sender][_trancheLength.sub(1)];
                trancheInfo[_pid][msg.sender].pop();
            }
        }
        // Note: Tranche's reward debt is issued on every deposit/withdrawal so that we don't count the full pool accumulation of ZORRO rewards.
        uint256 newTrancheShare = tranche.contribution.mul(1e12).div(pool.totalTrancheContributions);
        tranche.rewardDebt = pool.accZORRORewards.mul(newTrancheShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _trancheId, _wantAmt);

        return _wantAmt;
    }

    /// @notice Withdraws funds from a pool and converts the Want token into USDC
    /// @param _pid index of pool to deposit into
    /// @param _trancheId index of tranche
    /// @param _wantAmt value in Want tokens to withdraw (0 will result in harvest and uint256(-1) will result in max value)
    /// @return Amount (in USDC) returned
    function withdrawalFullService(uint256 _pid, uint256 _trancheId, uint256 _wantAmt) public nonReentrant returns (uint256) {
        // Call core withdrawal function (returns actual amount withdrawn)
        // TODO need to make withdraw() return value
        uint256 wantAmtWithdrawn = withdraw(_pid, _trancheId, _wantAmt);
        // Get library from pool
        address lib = poolInfo[_pid].lib;
        // Perform delegate call to autoswap and receive tokens and enter underlying vaults
        (bool success, bytes memory data) = lib.delegatecall(abi.encodeWithSignature("withdraw(uint256)", wantAmtWithdrawn));
        require(success, "delegatecall to withdraw() failed");
        // Parse and return amount data
        return abi.decode(data, (uint256));
        // TODO: Make sure deposit and withdrawal events are being emmitted in the right place
    }

    /// @notice Transfer all assets from a tranche in one vault to a new vault
    /// @param _fromPid index of pool FROM
    /// @param _fromTrancheId index of tranche FROM
    /// @param _toPid index of pool TO
    function transferInvestment(uint256 _fromPid, uint256 _fromTrancheId, uint256 _toPid) public nonReentrant {
        // Get weeks committed and entered at
        uint256 weeksCommitted = trancheInfo[_fromPid][msg.sender][_fromTrancheId].durationCommittedInWeeks;
        uint256 enteredVaultAt = trancheInfo[_fromPid][msg.sender][_fromTrancheId].enteredVaultAt;
        // Withdraw
        uint256 withdrawnUSDC = withdrawalFullService(_fromPid, _fromTrancheId, type(uint256).max);
        // Redeposit
        address[] memory sourceTokens;
        sourceTokens[0] = defaultStablecoin;
        _depositFullService(_toPid, withdrawnUSDC, sourceTokens, weeksCommitted, enteredVaultAt);
        emit TransferInvestment(msg.sender, _fromPid, _fromTrancheId, _toPid);
    }

    /// @notice Withdraw the maximum number of Want tokens from a pool
    /// @param _pid index of pool
    function withdrawAll(uint256 _pid) public nonReentrant {
        uint256 numTranches = trancheLength(_pid, msg.sender);
        for (uint256 tid = 0; tid < numTranches; ++tid) {
            withdraw(_pid, type(uint256).max, tid);
        }
    }

    /* Safety functions */

    /// @notice Safe ZORRO transfer function, just in case if rounding error causes pool to not have enough
    /// @param _to destination for funds
    /// @param _ZORROAmt quantity of Zorro tokens to send
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
    function inCaseTokensGetStuck(address _token, uint256 _amount)
        public
        onlyOwner
    {
        require(_token != ZORRO, "!safe to use Zorro token in func inCaseTokensGetStuck");
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }
}