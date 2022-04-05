// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../tokens/ZorroToken.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// TODO: Do thorough analysis to ensure enough setters/constructors
// TODO: Move all child state variables to their respective child contracts for better organization
// TODO: General: For everywhere we call a swap, let's make sure to do safe approval beforehand

/* Base Contract */

/// @title ZorroControllerBase: The base controller with main state variables, data types, and functions
contract ZorroControllerBase is Ownable, ReentrancyGuard {
    /* Libraries */
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* Modifiers */
    /// @notice Only allows functions to be executed where the sender matches the zorroPriceOracle address
    modifier onlyAllowZorroControllerOracle() {
        require(_msgSender() == zorroControllerOracle, "only Zorro oracle");
        _;
    }

    /* Structs */

    // Info of each tranche.
    struct TrancheInfo {
        uint256 contribution; // The tranche-specific contribution for a given pool (Cx). Equivalent to the product of their contributed deposit and a time multiplier
        uint256 timeMultiplier; // The time multiplier factor for rewards
        uint256 rewardDebt; // The tranche's share of the amount of rewards accumulated in the pool to date (see README)
        uint256 durationCommittedInWeeks; // How many weeks the user committed to at the time of deposit for this tranche
        uint256 enteredVaultAt; // The block timestamp for which the user deposited into a Vault.
        uint256 exitedVaultAt; // The block timestamp for which the user finished withdrawal
    }

    // Info of each pool
    struct PoolInfo {
        IERC20 want; // Want token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool.
        uint256 lastRewardBlock; // Last block number that ZORRO distribution occurs.
        uint256 accZORRORewards; // Accumulated ZORRO rewards in this pool
        uint256 totalTrancheContributions; // Sum of all user contributions in this pool
        address vault; // Address of the Vault
    }

    /* State */

    // Key tokens/addresses
    address public ZORRO;
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;
    address public publicPool; // Only to be set on home chain
    // Rewards
    uint256 public startBlock;
    uint256 public blocksPerDay = 28800; // Approximate, varies by chain
    uint256 public ZORROPerBlock; // Calculated according to Tokenomics
    uint256 public targetTVLCaptureBasisPoints; // 333 = 3.33% ONLY to be set on the home chain
    uint256 public ZORRODailyDistributionFactorBasisPointsMin = 1; // 1 = 0.01% ONLY for home chain
    uint256 public ZORRODailyDistributionFactorBasisPointsMax = 20; // 20 = 0.20% ONLY for home chain
    uint256 public chainMultiplier = 1; // Proportional rewards to be sent to this chain
    uint256 public baseRewardRateBasisPoints = 10;
    uint256 public totalAllocPoint = 0; // Total allocation points (aka multiplier). Must be the sum of all allocation points in all pools.
    // Stablecoins
    address public defaultStablecoin; // Address of default stablecoin (i.e. USDC)
    // Zorro Single Staking vault
    address public zorroStakingVault; // The vault for ZOR stakers on the home chain.
    // Cross-chain
    uint256 public chainId; // The ID/index of the chain that this contract is on
    uint256 public homeChainId = 0; // The chain ID of the home chain
    address public homeChainZorroController; // Address of the home chain ZorroController contract. For cross chain routing. "address" type because it's on the EVM
    // Info of each pool
    PoolInfo[] public poolInfo;
    // List of active tranches that stakes Want tokens. Mapping: pool ID/index => user wallet address on-chain => list of tranches
    mapping(uint256 => mapping(address => TrancheInfo[])) public trancheInfo;
    // Map of account address on chain for a given foreign account and pool. Mapping: pool index => foreign chain wallet address => Mapping(tranche ID => local account address)
    mapping(uint256 => mapping(bytes => mapping(uint256 => address))) public foreignTrancheInfo;
    // Oracles
    // TODO: Need constructors/setters.
    address public zorroControllerOracle;

    /* Setters */
    
    function setStartBlock(uint256 _blockNumber) external onlyOwner {
        startBlock = _blockNumber;
    }

    function setPublicPool(address _publicPoolAddress) external onlyOwner {
        publicPool = _publicPoolAddress;
    }

    function setBaseRewardRateBasisPoints(uint256 _baseRewardRateBasisPoints)
        external
        onlyOwner
    {
        baseRewardRateBasisPoints = _baseRewardRateBasisPoints;
    }

    function setTargetTVLCaptureBasisPoints(
        uint256 _targetTVLCaptureBasisPoints
    ) external onlyOwner {
        targetTVLCaptureBasisPoints = _targetTVLCaptureBasisPoints;
    }

    function setBlocksPerDay(uint256 _blocksPerDay) external onlyOwner {
        blocksPerDay = _blocksPerDay;
    }

    function setZORRODailyDistributionFactorBasisPointsMin(uint256 _value)
        external
        onlyOwner
    {
        ZORRODailyDistributionFactorBasisPointsMin = _value;
    }

    function setZORRODailyDistributionFactorBasisPointsMax(uint256 _value)
        external
        onlyOwner
    {
        ZORRODailyDistributionFactorBasisPointsMax = _value;
    }

    function setDefaultStablecoin(address _defaultStablecoin)
        external
        onlyOwner
    {
        defaultStablecoin = _defaultStablecoin;
    }

    function setHomeChainZorroController(address _homeChainZorroController)
        external
        onlyOwner
    {
        require(_homeChainZorroController != address(0), "cannot be 0 addr");
        homeChainZorroController = _homeChainZorroController;
    }

    function setZorroStakingVault(address _zorroStakingVault)
        external
        onlyOwner
    {
        zorroStakingVault = _zorroStakingVault;
    }

    function setChainId(uint256 _chainId) external onlyOwner {
        chainId = _chainId;
    }

    function setZorroControllerOracle(address _zorroControllerOracle) external onlyOwner {
        zorroControllerOracle = _zorroControllerOracle;
    }

    function setChainMultiplier(uint256 _chainMultiplier) external onlyOwner {
        chainMultiplier = _chainMultiplier;
    }

    /* View functions */

    /// @notice Number of pools in the Zorro protocol
    /// @return Number of pools
    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    /// @notice Number of tranches invested by a given user into a given pool
    /// @param _pid Index of pool
    /// @param _user wallet address of user
    /// @return Number of tranches
    function trancheLength(uint256 _pid, address _user)
        public
        view
        returns (uint256)
    {
        return trancheInfo[_pid][_user].length;
    }

    /* Zorro Rewards */

    /// @notice Set the number of Zorro to emit per block based on current market parameters
    /// @dev Values to be provided by Oracle. Perferable to run daily
    /// @param _totalChainMultipliers Sum total of all chain multipliers for each chain
    /// @param _totalMarketTVLUSD Total DeFi market TVL across all chains (measured in USD)
    /// @param _targetTVLCaptureBasisPoints % desired capture of total market TVL, measured in basis points
    /// @param _ZorroTotalVaultTVLUSD USD value of all TVL locked into the Zorro protocol, across all chains
    /// @param _publicPoolZORBalance Number of ZOR tokens remaining in public pool on home chain
    function setZorroPerBlock(
        uint256 _totalChainMultipliers,
        uint256 _totalMarketTVLUSD,
        uint256 _targetTVLCaptureBasisPoints,
        uint256 _ZorroTotalVaultTVLUSD,
        uint256 _publicPoolZORBalance
    ) external onlyAllowZorroControllerOracle {
        // Use the Rm formula to determine the percentage of the remaining public pool Zorro tokens to transfer to this contract as rewards
        uint256 ZORRODailyDistributionFactorBasisPoints = baseRewardRateBasisPoints
                .mul(_totalMarketTVLUSD)
                .mul(_targetTVLCaptureBasisPoints.div(10000))
                .div(_ZorroTotalVaultTVLUSD);
        // Rail distribution to min and max values
        if (
            ZORRODailyDistributionFactorBasisPoints >
            ZORRODailyDistributionFactorBasisPointsMax
        ) {
            ZORRODailyDistributionFactorBasisPoints = ZORRODailyDistributionFactorBasisPointsMax;
        } else if (
            ZORRODailyDistributionFactorBasisPoints <
            ZORRODailyDistributionFactorBasisPointsMin
        ) {
            ZORRODailyDistributionFactorBasisPoints = ZORRODailyDistributionFactorBasisPointsMin;
        }
        // Multiply the factor above to determine the total Zorro tokens to distribute to this contract on a DAILY basis
        uint256 publicPoolDailyZORRODistribution = _publicPoolZORBalance
                .mul(ZORRODailyDistributionFactorBasisPoints)
                .div(10000);
        // Determine the share of daily distribution for this chain
        uint256 chainDailyDist = chainMultiplier.mul(publicPoolDailyZORRODistribution).div(_totalChainMultipliers);
        // Convert this to a BLOCK basis and assign to ZORROPerBlock
        ZORROPerBlock = chainDailyDist.div(blocksPerDay);
    }

    /* Pool Management */

    /// @notice Update reward variables of the given pool to be up-to-date.
    /// @param _pid index of pool
    /// @return uint256 Amount of ZOR rewards minted (useful for cross chain)
    function updatePool(uint256 _pid) public returns (uint256) {
        // Get the pool matching the given index
        PoolInfo storage pool = poolInfo[_pid];

        // If current block is <= last reward block, exit
        if (block.number <= pool.lastRewardBlock) {
            return 0;
        }

        // Determine how many blocks have elapsed since the last updatePool() operation for this pool
        uint256 elapsedBlocks = block.number.sub(pool.lastRewardBlock);
        // If no elapsed blocks have occured, exit
        if (elapsedBlocks <= 0) {
            return 0;
        }

        // Finally, multiply rewards/block by the number of elapsed blocks and the pool weighting
        uint256 ZORROReward = elapsedBlocks
            .mul(ZORROPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);

        // Check whether this function requires cross chain activity or not
        if (address(this) == homeChainZorroController) {
            // On Home chain. NO cross chain pool updates required

            // Transfer Zorro rewards to this contract from the Public Pool
            IERC20(ZORRO).safeTransferFrom(
                publicPool,
                address(this),
                ZORROReward
            );
            // Increment this pool's accumulated Zorro per share value by the reward amount
            pool.accZORRORewards = pool.accZORRORewards.add(ZORROReward);
            // Update the pool's last reward block to the current block
            pool.lastRewardBlock = block.number;
            // Return 0, no ZOR minted because we're on chain
            return 0;
        } else {
            // On remote chain. Cross chain pool updates required

            // Mint Zorro on this (remote) chain
            Zorro(ZORRO).mint(address(this), ZORROReward);
            // Return ZOR minted
            return ZORROReward;
        }
    }

    /* Safety functions */

    /// @notice Safe ZORRO transfer function, just in case if rounding error causes pool to not have enough
    /// @param _to destination for funds
    /// @param _ZORROAmt quantity of Zorro tokens to send
    function _safeZORROTransfer(address _to, uint256 _ZORROAmt) internal {
        uint256 _xferAmt = _ZORROAmt;
        uint256 ZORROBal = IERC20(ZORRO).balanceOf(address(this));
        if (_ZORROAmt > ZORROBal) {
            _xferAmt = ZORROBal;
        }
        IERC20(ZORRO).safeTransfer(_to, _xferAmt);
    }

    /// @notice For owner to recover ERC20 tokens on this contract if stuck
    /// @dev Does not permit usage for the Zorro token
    /// @param _token ERC20 token address
    /// @param _amount token quantity
    function inCaseTokensGetStuck(address _token, uint256 _amount)
        public
        onlyOwner
    {
        require(
            _token != ZORRO,
            "!safe to use Zorro token in func inCaseTokensGetStuck"
        );
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }
}
