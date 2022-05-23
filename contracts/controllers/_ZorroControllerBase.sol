// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/IZorro.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "../interfaces/IZorroController.sol";

import "../interfaces/IVault.sol";

/* Base Contract */

/// @title ZorroControllerBase: The base controller with main state variables, data types, and functions
contract ZorroControllerBase is
    IZorroControllerBase,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /* Libraries */
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* Modifiers */
    /// @notice Only allows functions to be executed where the sender matches the zorroPriceOracle address
    modifier onlyAllowZorroControllerOracle() {
        require(_msgSender() == zorroControllerOracle, "only Zorro oracle");
        _;
    }

    /// @notice Only allows functions to be executed on contracts matching the home chain controller
    modifier onlyHomeChain() {
        require(address(this) == homeChainZorroController, "only home chain");
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
        IERC20Upgradeable want; // Want token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool.
        uint256 lastRewardBlock; // Last block number that ZORRO distribution occurs.
        uint256 accZORRORewards; // Accumulated ZORRO rewards in this pool
        uint256 totalTrancheContributions; // Sum of all user contributions in this pool
        address vault; // Address of the Vault
    }

    /* Constants */

    // TODO: Make this a variable
    address public constant burnAddress =
        0x000000000000000000000000000000000000dEaD;

    /* State */

    // Key tokens/addresses
    address public ZORRO;
    address public defaultStablecoin; // Address of default stablecoin (i.e. USDC)
    address public publicPool; // Only to be set on home chain
    address public zorroStakingVault; // The vault for ZOR stakers on the home chain.
    // Rewards
    uint256 public startBlock;
    uint256 public blocksPerDay; // Approximate, varies by chain
    uint256 public ZORROPerBlock; // Calculated according to Tokenomics
    uint256 public targetTVLCaptureBasisPoints; // 333 = 3.33% ONLY to be set on the home chain
    uint256 public ZORRODailyDistributionFactorBasisPointsMin; // 1 = 0.01% ONLY for home chain
    uint256 public ZORRODailyDistributionFactorBasisPointsMax; // 20 = 0.20% ONLY for home chain
    uint256 public chainMultiplier; // Proportional rewards to be sent to this chain
    uint256 public baseRewardRateBasisPoints;
    uint256 public totalAllocPoint; // Total allocation points (aka multiplier). Must be the sum of all allocation points in all pools.
    // Cross-chain
    uint256 public chainId; // The ID/index of the chain that this contract is on
    uint256 public homeChainId; // The chain ID of the home chain
    address public homeChainZorroController; // Address of the home chain ZorroController contract. For cross chain routing. "address" type because it's on the EVM
    // Info of each pool
    PoolInfo[] public poolInfo;
    // List of active tranches that stakes Want tokens. Mapping: pool ID/index => user wallet address on-chain => list of tranches
    mapping(uint256 => mapping(address => TrancheInfo[])) public trancheInfo;
    // Map of account address on chain for a given foreign account and pool. Mapping: pool index => foreign chain wallet address => Mapping(tranche ID => local account address)
    mapping(uint256 => mapping(bytes => mapping(uint256 => address)))
        public foreignTrancheInfo;
    // Oracles
    address public zorroControllerOracle;

    /* Setters */

    /// @notice Setter: Set key token addresses
    /// @param _ZORRO ZOR token address
    /// @param _defaultStablecoin Main stablecoin address (USDC)
    function setKeyAddresses(address _ZORRO, address _defaultStablecoin)
        external
        onlyOwner
    {
        ZORRO = _ZORRO;
        defaultStablecoin = _defaultStablecoin;
    }

    /// @notice Setter: Set key ZOR contract addresses
    /// @param _publicPool Public pool address (where ZOR minted)
    /// @param _zorroStakingVault Zorro single staking vault address
    function setZorroContracts(address _publicPool, address _zorroStakingVault)
        external
        onlyOwner
        onlyHomeChain
    {
        publicPool = _publicPool;
        zorroStakingVault = _zorroStakingVault;
    }

    /// @notice Setter: Start block for rewards
    function setStartBlock(uint256 _startBlock) external onlyOwner {
        // Set start block only if it hasn't been set previously
        require(startBlock == 0, "blockParams immutable");
        startBlock = _startBlock;
    }

    /// @notice Setter: Reward params (See Tokenomics paper for more details)
    /// @dev NOTE: Must enter all parameters or existing ones will be overwritten!
    /// @param _blocksPerDay # of blocks per day for this chain
    /// @param _dailyDistFactors Array of [ZORRODailyDistributionFactorBasisPointsMin, ZORRODailyDistributionFactorBasisPointsMax]
    /// @param _chainMultiplier Rewards multiplier factor to be applied to this chain
    /// @param _baseRewardRateBasisPoints Base reward rate factor, in bp
    function setRewardsParams(
        uint256 _blocksPerDay,
        uint256[] calldata _dailyDistFactors,
        uint256 _chainMultiplier,
        uint256 _baseRewardRateBasisPoints
    ) external onlyOwner {
        // Set block production rate for this chain
        blocksPerDay = _blocksPerDay;

        // Tokenomics
        ZORRODailyDistributionFactorBasisPointsMin = _dailyDistFactors[0];
        ZORRODailyDistributionFactorBasisPointsMax = _dailyDistFactors[1];
        baseRewardRateBasisPoints = _baseRewardRateBasisPoints;

        // Chain multiplier
        chainMultiplier = _chainMultiplier;
    }

    /// @notice Setter: TVL capture (See Tokenomics paper)
    /// @param _targetTVLCaptureBasisPoints Percent of market desired to be captured, in bp. 333 = 3.33%. ONLY to be set on the home chain
    function setTargetTVLCaptureBasisPoints(
        uint256 _targetTVLCaptureBasisPoints
    ) external onlyOwner onlyHomeChain {
        targetTVLCaptureBasisPoints = _targetTVLCaptureBasisPoints;
    }

    /// @notice Setter: Cross chain params
    /// @param _chainId The ind of the chain that this contract is on
    /// @param _homeChainId The chain ID of the home chain
    /// @param _homeChainZorroController The address of the home chain controller
    function setXChainParams(
        uint256 _chainId,
        uint256 _homeChainId,
        address _homeChainZorroController
    ) external onlyOwner {
        chainId = _chainId;
        homeChainId = _homeChainId;
        homeChainZorroController = _homeChainZorroController;
    }

    /// @notice Setter: Set Zorro Controller Oracle
    /// @param _zorroControllerOracle Address of Chainlink oracle that can interact with this contract
    function setZorroControllerOracle(address _zorroControllerOracle)
        external
        onlyOwner
    {
        zorroControllerOracle = _zorroControllerOracle;
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
                .mul(_targetTVLCaptureBasisPoints)
                .div(_ZorroTotalVaultTVLUSD.mul(10000));

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
        // And then multiply by the share of daily distribution for this chain
        // Finally: Convert this to a BLOCK basis and assign to ZORROPerBlock
        ZORROPerBlock = _publicPoolZORBalance
            .mul(ZORRODailyDistributionFactorBasisPoints)
            .mul(chainMultiplier)
            .div(_totalChainMultipliers.mul(10000).mul(blocksPerDay));
    }

    /* Pool Management */

    /// @notice Update reward variables of the given pool to be up-to-date.
    /// @param _pid index of pool
    /// @return mintedZOR Amount of ZOR rewards minted (useful for cross chain)
    function updatePool(uint256 _pid) public returns (uint256 mintedZOR) {
        // Get the pool matching the given index
        PoolInfo storage pool = poolInfo[_pid];

        // If current block is <= last reward block, exit
        if (block.number <= pool.lastRewardBlock) {
            return 0;
        }

        // If underlying vault's shares are zero, skip
        uint256 sharesTotal = IVault(pool.vault).sharesTotal();
        if (sharesTotal == 0) {
            pool.lastRewardBlock = block.number;
            return 0;
        }

        // Determine how many blocks have elapsed since the last updatePool() operation for this pool
        uint256 elapsedBlocks = block.number.sub(pool.lastRewardBlock);

        // Finally, multiply rewards/block by the number of elapsed blocks and the pool weighting
        uint256 ZORROReward = elapsedBlocks
            .mul(ZORROPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);

        // Check whether this function requires cross chain activity or not
        if (address(this) == homeChainZorroController) {
            // On Home chain. NO cross chain pool updates required

            // Transfer Zorro rewards to this contract from the Public Pool
            _fetchFundsFromPublicPool(ZORROReward);

            // Return 0, no ZOR minted because we're on chain
            mintedZOR = 0;
        } else {
            // On remote chain. Cross chain pool updates required

            // Mint Zorro on this (remote) chain
            IZorro(ZORRO).mint(address(this), ZORROReward);
            
            // Return ZOR minted
            mintedZOR = ZORROReward;
        }

        // Increment this pool's accumulated Zorro per share value by the reward amount
        pool.accZORRORewards = pool.accZORRORewards.add(ZORROReward);
        // Update the pool's last reward block to the current block
        pool.lastRewardBlock = block.number;
    }

    /// @notice Gets the specified amount of ZOR tokens from the public pool and transfers to this contract
    /// @param _amount The amount to fetch from the public pool
    function _fetchFundsFromPublicPool(uint256 _amount) internal virtual {
        IERC20Upgradeable(ZORRO).safeTransferFrom(
            publicPool,
            address(this),
            _amount
        );
    }

    /* Safety functions */

    /// @notice Safe ZORRO transfer function, just in case if rounding error causes pool to not have enough
    /// @param _to destination for funds
    /// @param _ZORROAmt quantity of Zorro tokens to send
    function _safeZORROTransfer(address _to, uint256 _ZORROAmt) internal {
        uint256 _xferAmt = _ZORROAmt;
        uint256 ZORROBal = IERC20Upgradeable(ZORRO).balanceOf(address(this));
        if (_ZORROAmt > ZORROBal) {
            _xferAmt = ZORROBal;
        }
        IERC20Upgradeable(ZORRO).safeTransfer(_to, _xferAmt);
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
        IERC20Upgradeable(_token).safeTransfer(msg.sender, _amount);
    }
}
