// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/SafeERC20.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../helpers/Ownable.sol";

import "../helpers/ReentrancyGuard.sol";

import "../tokens/ZorroTokens.sol"; // TODO: Consider using SafeERC20/OZ helper functions here

import "../cross-chain/XchainEndpoint.sol";


/* Base Contract */

/// @title ZorroControllerBase: The base controller with main state variables, data types, and functions
contract ZorroControllerBase is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using Math for uint256; // TODO: Do we need both Math and SafeMath?
    using SafeERC20 for IERC20;

    /* Structs */

    // Info of each tranche.
    struct TrancheInfo {
        uint256 contribution; // The tranche-specific contribution for a given pool (Cx). Equivalent to the product of their contributed deposit and a time multiplier
        uint256 timeMultiplier; // The time multiplier factor for rewards
        uint256 rewardDebt; // The tranche's share of the amount of rewards accumulated in the pool to date (see README)
        uint256 durationCommittedInWeeks; // How many weeks the user committed to at the time of deposit for this tranche
        uint256 enteredVaultAt; // The block timestamp for which the user deposited into a Vault.
        uint256 exitedVaultStartingAt; // The block timestamp for which the user attempted withdrawal (useful for tracking cross chain withdrawals)
    }

    // Info of each pool
    struct PoolInfo {
        IERC20 want; // Want token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool.
        uint256 lastRewardBlock; // Last block number that ZORRO distribution occurs.
        uint256 accZORRORewards; // Accumulated ZORRO rewards in this pool
        uint256 totalTrancheContributions; // Sum of all user contributions in this pool
        address vault; // Address of the Vault
        address intermediaryToken; // Token that the protocol returns after claiming (e.g. on Tranchess) (usually a stablecoin like USDC)
    }

    // Claim
    struct Claim {
        uint256 preSettlementAmount; // Amount of tokens bought/sold of origin token, before settlement
        uint256 settlementEpoch; // The anticipated settlement epoch
        bool settled; // Whether trade has been settled
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
    // TODO: Are defaultStablecoin, syntheticStablecoin needed anymore?
    address public defaultStablecoin; // TODO: Setter/constructor
    address public syntheticStablecoin; // TODO: Setter/constructor
    int128 public defaultStablecoinIndex; // Index in Curve metapool of default stablecoin (e.g. USDC) TODO: Setter/constructor
    int128 public synthethicStablecoinIndex; // Index in Curve metapool of synthetic stablecoin (e.g. zUSDC) TODO: Setter/constructor
    mapping(uint256 => address) public endpointContracts; // Mapping of chain ID to endpoint contract
    address public lockUSDCController; // TODO: Put in setter, constructor
    address public uniRouterAddress; // Router contract address for adding/removing liquidity, etc. TODO: Put in setter/getter
    address public curveStablePoolAddress; // Pool contract address for swapping stablecoins TODO: Put in setter/getter
    address public homeChainZorroController; // Address of the home (BSC) chain ZorroController contract. For cross chain routing. TODO: setter/constructor TODO: Make sure homecontrollercontract can never be address(0)!
    uint256 public chainId; // TODO: Setter, contructor. The ID/index of the chain that this contract is on
    // TODO: Do thorough analysis to ensure enough setters/constructors
    mapping(uint256 => mapping(uint256 => uint8)) public lockedEarningsStatus; // Tracks status of cross chain locked earnings. Mapping: block number => pid => status. Statuses: 0: None, 1: Pending, 2: Completed successfully, 3: Failed. TODO: Turn these numbers into enums
    uint256 public failedLockedBuybackUSDC; // Accumulated amount of locked earnings for buyback that were failed from previous cross chain attempts
    uint256 public failedLockedRevShareUSDC; // Accumulated amount of locked earnings for revshare that were failed from previous cross chain attempts
    uint256 public defaultMaxMarketMovement = 970; // Max default slippage, divided by 1000. E.g. 970 means 1 - 970/1000 = 3%. TODO: Setter
    address public zorroLPPool; // TODO: Constructor, setter. Main pool for Zorro liquidity
    address public zorroLPPoolToken0; // TODO: Constructor, setter. For the dominant LP pool, the 0th token (usually ZOR)
    address public zorroLPPoolToken1; // TODO: Constructor, setter. For the dominant LP pool, the 1st token
    address public zorroStakingVault; // TODO: Constructor, setter. The vault for ZOR stakers on the BSC chain.
    address[] public USDCToZORPath; // TODO: Constructor, setter. The router path from USDC to ZOR
    address[] public USDCToZorroLPPoolToken0Path; // TODO: Constructor, setter. The router path from USDC to the primary Zorro LP pool, Token 0
    address[] public USDCToZorroLPPoolToken1Path; // TODO: Constructor, setter. The router path from USDC to the primary Zorro LP pool, Token 1

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
    function setEndpointContracts(uint256 _chainId, address _endpointContract) external onlyOwner {
        endpointContracts[_chainId] = _endpointContract;
    }


    // Info of each pool
    PoolInfo[] public poolInfo;
    // List of active tranches that stakes Want tokens. Mapping: pool ID/index => user wallet address => list of tranches
    mapping(uint256 => mapping(address => TrancheInfo[])) public trancheInfo; 
    // Total allocation points (aka multiplier). Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // TODO: Do we even need claims anymore? Consider doing a global removal of "claim" related stuff
    // Claims for user by pool ID (e.g. for Tranchess). Mapping pool ID/index => user wallet address => token address => claim amount
    mapping(uint256 => mapping(address => mapping(address => Claim))) public claims;
    // Redeposit information (so contract knows settings for destination vault during an async redeposit event)
    // Mapping: pool ID/index => user wallet address => RedepositInfo
    mapping(uint256 => mapping(address => RedepositInfo)) public redepositInfo;

    /* Events */
    event Deposit(address indexed user, uint256 indexed pid, uint256 wantAmount);
    event ClaimCreated(address indexed user, uint256 indexed pid, uint256 indexed settlementEpoch, uint256 value, address token);
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
        /*
        - TODO: This should be done automatically by an Oracle and stored as ZORROPerBlock fetch current Zorro per block, and divide by this chain's block producing rate / BSC block producing rate
        */

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

        // Check whether this function requires cross chain activity or not
        if (address(this) == homeChainZorroController) {
            // On Home chain. NO cross chain pool updates required

            // Transfer Zorro rewards to this contract from the Public Pool
            IERC20(ZORRO).safeTransferFrom(publicPool, address(this), ZORROReward);
            // Increment this pool's accumulated Zorro per share value by the reward amount
            pool.accZORRORewards = pool.accZORRORewards.add(ZORROReward);
            // Update the pool's last reward block to the current block
            pool.lastRewardBlock = block.number;
        } else {
            // On remote chain. Cross chain pool updates required

            // Mint Zorro on this (remote) chain
            Zorro(ZORRO).mint(address(this), ZORROReward);
            // Get endpoint contract
            address homeChainEndpointContract = endpointContracts[0]; // TODO: Is it safe to use the zero index here or should we declare a state variable for the home contract?
            // Make cross-chain burn request
            // TODO: Revert action should indicate failure for burn request and accumulate it so that the next burn request will include it
            XChainEndpoint(homeChainEndpointContract).sendXChainTransaction(
                abi.encodePacked(homeChainZorroController),
                abi.encodeWithSignature("receiveXChainBurnRewardsRequest(uint256 _amount)", ZORROReward),
                ""
            );
        }
    }

    /// @notice Receives an authorized burn request from another chain and burns the specified amount of ZOR tokens from the public pool
    /// @param _amount The quantity of ZOR tokens to burn
    function receiveXChainBurnRewardsRequest(uint256 _amount) external {
        // TODO IMPORTANT: Only allow valid contract (endpoint contract?) to call this
        Zorro(ZORRO).burn(publicPool, _amount); // TODO: Should we wrap this in Open Zeppelin somehow?
    }
    /* Safety functions */

    /// @notice Safe ZORRO transfer function, just in case if rounding error causes pool to not have enough
    /// @param _to destination for funds
    /// @param _ZORROAmt quantity of Zorro tokens to send
    function safeZORROTransfer(address _to, uint256 _ZORROAmt) internal {
        uint256 ZORROBal = IERC20(ZORRO).balanceOf(address(this));
        // TODO: Change this to a safeTransfer() function (OpenZeppelin compliance)
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
