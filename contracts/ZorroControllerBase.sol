// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./libraries/SafeERC20.sol";

import "./libraries/Math.sol";

import "./libraries/SafeMath.sol";

import "./helpers/Ownable.sol";

import "./helpers/ReentrancyGuard.sol";

/* Base Contract */

/// @title ZorroControllerBase: The base controller with main state variables, data types, and functions
contract ZorroControllerBase is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using Math for uint256;
    using SafeERC20 for IERC20;

    /* Constructor */

    /// @notice Constructor
    /// @param _timelockOwner address of owner (should be a timelock)
    /// @param _zorroToken address of Zorro token
    /// @param _startBlock start block number. If current block is below this number, rewards won't be emitted. https://bscscan.com/block/countdown/13650292
    /// @param _publicPool address of the public pool to draw rewards from
    /// @param _BSCMarketTVLUSD total market TVL on the BSC chain in USD
    /// @param _ZorroTotalVaultTVLUSD total TVL locked into the Zorro protocol across all vaults
    /// @param _targetTVLCaptureBasisPoints how many basis points of the BSC total market TVL the protocol desires to capture (influences market aware emissions calcs)
    constructor(
        address _timelockOwner,
        address _zorroToken,
        uint256 _startBlock,
        address _publicPool,
        uint256 _BSCMarketTVLUSD,
        uint256 _ZorroTotalVaultTVLUSD,
        uint256 _targetTVLCaptureBasisPoints,
        address _defaultStablecoin
    ) {
        // Assign owner as to timelock contract
        transferOwnership(_timelockOwner);
        // Set main state variables to initial state
        ZORRO = _zorroToken;
        startBlock = _startBlock;
        publicPool = _publicPool;
        BSCMarketTVLUSD = _BSCMarketTVLUSD; 
        ZorroTotalVaultTVLUSD = _ZorroTotalVaultTVLUSD; 
        targetTVLCaptureBasisPoints = _targetTVLCaptureBasisPoints;
        defaultStablecoin = _defaultStablecoin;
    }

    /* Structs */

    // Info of each tranche.
    struct TrancheInfo {
        uint256 contribution; // The tranche-specific contribution for a given pool (Cx). Equivalent to the product of their contribution and a time multiplier
        uint256 timeMultiplier; // The time multiplier factor for rewards
        uint256 rewardDebt; // The tranche's share of the amount of rewards accumulated in the pool to date (see README)
        uint256 durationCommittedInWeeks; // How many weeks the user committed to at the time of deposit for this tranche
        uint256 enteredVaultAt; // The block timestamp for which the user deposited into a Vault.
    }

    // Info of each pool
    struct PoolInfo {
        IERC20 want; // Want token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool.
        uint256 lastRewardBlock; // Last block number that ZORRO distribution occurs.
        uint256 accZORRORewards; // Accumulated ZORRO rewards in this pool
        uint256 totalTrancheContributions; // Sum of all user contributions in this pool
        address vault; // Address of the Vault
        address lib; // Address of deployed library for this pool
        address intermediaryToken; // Token that the protocol returns after claiming (e.g. on Tranchess) (usually a stablecoin like USDC)
    }

    // Claim
    struct Claim {
        uint256 amount;
        uint256 reason; // 0: deposit, 1: withdrawal, 2: transfer
    }
    // Redeposit information for async flows
    struct RedepositInfo {
        uint256 durationCommittedInWeeks; // Original number of weeks committed for previous vault (pre-redeposit)
        uint256 enteredVaultAt; // Original entry timestamp for previous vault (pre-redeposit)
    }

    /* Variables */ 

    // Public variables and their initial values (check blockchain scanner for latest values)
    // See constructor() for explanations
    address public ZORRO;
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;
    uint256 public startBlock;
    address public publicPool; 
    uint256 public baseRewardRateBasisPoints = 10;
    uint256 public BSCMarketTVLUSD; 
    uint256 public ZorroTotalVaultTVLUSD;
    uint256 public targetTVLCaptureBasisPoints; // 333 = 3.33%
    uint256 public blocksPerDay = 28800; // Approximate
    uint256 public ZORRODailyDistributionFactorBasisPointsMin = 1; // 1 = 0.01%
    uint256 public ZORRODailyDistributionFactorBasisPointsMax = 20; // 20 = 0.20%
    bool public isTimeMultiplierActive = true; // If true, allows use of time multiplier
    address public defaultStablecoin;

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
    // Claims for user by pool ID (e.g. for Tranchess). Mapping pool ID/index => user wallet address => token address => claim amount
    mapping(uint256 => mapping(address => mapping(address => Claim))) public claims;
    // Redeposit information (so contract knows settings for destination vault during an async redeposit event)
    // Mapping: pool ID/index => user wallet address => RedepositInfo
    mapping(uint256 => mapping(address => RedepositInfo)) public redepositInfo;

    /* Events */
    event Deposit(address indexed user, uint256 indexed pid, uint256 wantAmount);
    event ClaimCreated(address indexed user, uint256 indexed pid, uint256 value, address token);
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

    /* Zorro Rewards */

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

    /* Pool Management */

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
