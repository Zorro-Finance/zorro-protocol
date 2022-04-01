// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../tokens/ZorroTokens.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// TODO: Do thorough analysis to ensure enough setters/constructors
// TODO: Generally: Convert uint8s to enums
// TODO: Do we have an infinite loop problem with cross chain reverts?

/* Base Contract */

/// @title ZorroControllerBase: The base controller with main state variables, data types, and functions
contract ZorroControllerBase is Ownable, ReentrancyGuard {
    /* Libraries */
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* Modifiers */
    /// @notice Only allows functions to be executed where the sender matches the authorizedOracle address
    modifier onlyXChainEndpoints() {
        require(
            registeredXChainEndpoints[_msgSender()] > 0,
            "only reg xchain endpoints"
        );
        _;
    }

    /// @notice Only allows functions to be executed where the sender matches one of the authorized Zorro controllers
    modifier onlyXChainZorroControllers(bytes memory _xChainSender) {
        require(
            registeredXChainControllers[_xChainSender],
            "only reg xchain controllers"
        );
        _;
    }

    /// @notice Only allows functions to be executed where the sender matches the zorroPriceOracle address
    modifier onlyAllowZorroControllerOracle() {
        require(_msgSender() == zorroControllerOracle, "only Zorro oracle");
        _;
    }

    /// @notice Only can be called from a registered vault
    /// @param _pid The pool ID
    modifier onlyRegisteredVault(uint256 _pid) {
        require(_msgSender() == poolInfo[_pid].vault, "only reg vault");
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
        uint256 exitedVaultStartingAt; // The block timestamp for which the user attempted withdrawal (useful for tracking cross chain withdrawals)
    }

    // Info of foreign tranche
    struct ForeignTrancheInfo {
        uint256 trancheIndex; // Index of tranche in trancheInfo
        address localAccount; // Use account on chain
    }

    // Stargate swaps
    struct StargateSwapPayload {
        uint256 chainId;
        uint256 qty;
        bytes dstContract;
        bytes payload;
        uint256 maxMarketMovement;
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

    // Redeposit information for async flows
    struct RedepositInfo {
        uint256 durationCommittedInWeeks; // Original number of weeks committed for previous vault (pre-redeposit)
        uint256 enteredVaultAt; // Original entry timestamp for previous vault (pre-redeposit)
    }

    /* Variables */

    // Public variables and their initial values (check blockchain scanner for latest values)
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
    bool public isTimeMultiplierActive = true; // If true, allows use of time multiplier
    uint256 public baseRewardRateBasisPoints = 10;
    // Stablecoins
    address public defaultStablecoin; // Address of default stablecoin (i.e. USDC)
    address public syntheticStablecoin; // Address of synthetic stablecoin (i.e. ZUSDC)
    // Curve
    address public curveStablePoolAddress; // Pool contract address for swapping stablecoins
    int128 public curveDefaultStablecoinIndex; // Index in Curve metapool of default stablecoin (e.g. USDC)
    int128 public curveSyntheticStablecoinIndex; // Index in Curve metapool of synthetic stablecoin (e.g. zUSDC)
    // Zorro LP pool
    address public zorroLPPool; // Main pool for Zorro liquidity
    address public zorroLPPoolToken0; // For the dominant LP pool, the 0th token (usually ZOR)
    address public zorroLPPoolToken1; // For the dominant LP pool, the 1st token
    // Uni swaps
    address public uniRouterAddress; // Router contract address for adding/removing liquidity, etc.
    address[] public USDCToZorroLPPoolToken0Path; // The router path from USDC to the primary Zorro LP pool, Token 0
    address[] public USDCToZorroLPPoolToken1Path; // The router path from USDC to the primary Zorro LP pool, Token 1
    address[] public USDCToZorroPath; // The path to swap USDC to ZOR
    uint256 public defaultMaxMarketMovement = 970; // Max default slippage, divided by 1000. E.g. 970 means 1 - 970/1000 = 3%.

    // Zorro Single Staking vault
    address public zorroStakingVault; // The vault for ZOR stakers on the home chain.

    // Cross-chain
    address public homeChainZorroController; // Address of the home chain ZorroController contract. For cross chain routing.
    // TODO: Maybe convert to uint16?
    uint256 public chainId; // The ID/index of the chain that this contract is on
    uint8 public homeChainId = 0; // The chain ID of the home chain
    mapping(uint256 => address) public endpointContracts; // Mapping of chain ID to endpoint contract
    mapping(address => uint8) public registeredXChainEndpoints; // The accepted list of cross chain endpoints that can call this contract. Mapping: address => 0 = non existent. 1 = allowed.
    mapping(bytes => bool) public registeredXChainControllers; // Accepted list of cross chain Zorro controllers that can call this controller
    address public lockUSDCController;
    uint256 public failedLockedBuybackUSDC; // Accumulated amount of locked earnings for buyback that were failed from previous cross chain attempts
    uint256 public failedLockedRevShareUSDC; // Accumulated amount of locked earnings for revshare that were failed from previous cross chain attempts
    address public xChainReceivingOracle; // Address of the oracle that is authorized to make calls to this contract (usually for reverts)
    // TODO: Setters/contructors needed
    mapping(uint256 => uint16) public stargateZorroChainMap; // Mapping of Zorro Chain ID to Stargate/LayerZero Chain ID
    mapping(uint16 => uint256) public zorroStargateChainMap; // Mapping of Stargate/LayerZero Chain ID to Zorro Chain ID
    address public stargateRouter; // Address to on-chain Stargate router
    uint256 public stargateSwapPoolId; // Address of the pool to swap from on this contract
    mapping(uint256 => uint256) public stargateDestPoolIds; // Mapping from Zorro chain ID to Stargate dest Pool for the same token

    // Oracles
    AggregatorV3Interface internal _priceFeedLPPoolToken0;
    AggregatorV3Interface internal _priceFeedLPPoolToken1;
    address public zorroControllerOracle;
    uint256 public zorroControllerOracleFee;
    bytes32 public zorroControllerOraclePriceJobId;
    bytes32 public zorroControllerOracleEmissionsJobId;

    // Info of each pool
    PoolInfo[] public poolInfo;
    // List of active tranches that stakes Want tokens. Mapping: pool ID/index => user wallet address on-chain => list of tranches
    mapping(uint256 => mapping(address => TrancheInfo[])) public trancheInfo;
    // List of active tranches for a given foreign account and pool. Mapping: pool index => foreign chain wallet address => list of ForeignTrancheInfo
    mapping(uint256 => mapping(bytes => ForeignTrancheInfo[])) public foreignTrancheInfo;

    // Total allocation points (aka multiplier). Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // Redeposit information (so contract knows settings for destination vault during an async redeposit event)
    // Mapping: pool ID/index => user wallet address => RedepositInfo
    mapping(uint256 => mapping(address => RedepositInfo)) public redepositInfo;

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

    function setIsTimeMultiplierActive(bool _isActive) external onlyOwner {
        isTimeMultiplierActive = _isActive;
    }

    function setEndpointContracts(uint256 _chainId, address _endpointContract)
        external
        onlyOwner
    {
        endpointContracts[_chainId] = _endpointContract;
    }

    function setDefaultStablecoin(address _defaultStablecoin)
        external
        onlyOwner
    {
        defaultStablecoin = _defaultStablecoin;
    }

    function setSyntheticStablecoin(address _syntheticStablecoin)
        external
        onlyOwner
    {
        syntheticStablecoin = _syntheticStablecoin;
    }

    function setCurveStablePoolAddress(address _curveStablePoolAddress)
        external
        onlyOwner
    {
        curveStablePoolAddress = _curveStablePoolAddress;
    }

    function setLockUSDCController(address _lockUSDCController)
        external
        onlyOwner
    {
        lockUSDCController = _lockUSDCController;
    }

    function setUniRouter(address _uniV2Router) external onlyOwner {
        uniRouterAddress = _uniV2Router;
    }

    function setHomeChainZorroController(address _homeChainZorroController)
        external
        onlyOwner
    {
        require(_homeChainZorroController != address(0), "cannot be 0 addr");
        homeChainZorroController = _homeChainZorroController;
    }

    function setZorroLPPool(address _zorroLPPool) external onlyOwner {
        zorroLPPool = _zorroLPPool;
    }

    function setZorroLPPoolToken0(address _token0) external onlyOwner {
        zorroLPPoolToken0 = _token0;
    }

    function setZorroLPPoolToken1(address _token1) external onlyOwner {
        zorroLPPoolToken1 = _token1;
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

    function registerXChainEndpoint(address _contract) external onlyOwner {
        registeredXChainEndpoints[_contract] = 1;
    }

    function unRegisterXChainEndpoint(address _contract) external onlyOwner {
        registeredXChainEndpoints[_contract] = 0;
    }

    function registerXChainController(bytes memory _contract) external onlyOwner {
        registeredXChainControllers[_contract] = true;
    }

    function unRegisterXChainController(bytes memory _contract) external onlyOwner {
        registeredXChainControllers[_contract] = false;
    }

    function setXChainReceivingOracle(address _xChainReceivingOracle) external onlyOwner {
        xChainReceivingOracle = _xChainReceivingOracle;
    }

    function setUSDCToZorroLPPoolToken0Path(address[] memory _path)
        external
        onlyOwner
    {
        USDCToZorroLPPoolToken0Path = _path;
    }

    function setUSDCToZorroLPPoolToken1Path(address[] memory _path)
        external
        onlyOwner
    {
        USDCToZorroLPPoolToken1Path = _path;
    }

    function setDefaultMaxMarketMovement(uint256 _defaultMaxMarketMovement)
        external
        onlyOwner
    {
        defaultMaxMarketMovement = _defaultMaxMarketMovement;
    }

    function setPriceFeedLPPoolToken0(address _priceFeedLPPoolToken)
        external
        onlyOwner
    {
        _priceFeedLPPoolToken0 = AggregatorV3Interface(_priceFeedLPPoolToken);
    }

    function setPriceFeedLPPoolToken1(address _priceFeedLPPoolToken)
        external
        onlyOwner
    {
        _priceFeedLPPoolToken1 = AggregatorV3Interface(_priceFeedLPPoolToken);
    }

    function setZorroControllerOracle(address _zorroControllerOracle) external onlyOwner {
        zorroControllerOracle = _zorroControllerOracle;
    }

    function setZorroControllerOracleFee(uint256 _zorroControllerOracleFee)
        external
        onlyOwner
    {
        zorroControllerOracleFee = _zorroControllerOracleFee;
    }

    function setZorroControllerOraclePriceJobId(bytes32 _zorroControllerOraclePriceJobId)
        external
        onlyOwner
    {
        zorroControllerOraclePriceJobId = _zorroControllerOraclePriceJobId;
    }

    function setZorroControllerOracleEmissionsJobId(bytes32 _zorroControllerOracleEmissionsJobId)
        external
        onlyOwner
    {
        zorroControllerOracleEmissionsJobId = _zorroControllerOracleEmissionsJobId;
    }

    function setChainMultiplier(uint256 _chainMultiplier) external onlyOwner {
        chainMultiplier = _chainMultiplier;
    }

    /* Events */
    event Deposit(
        address indexed user,
        uint256 indexed pid,
        uint256 wantAmount
    );
    event Withdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 trancheId,
        uint256 wantAmount
    );
    event TransferInvestment(
        address user,
        uint256 indexed fromPid,
        uint256 indexed fromTrancheId,
        uint256 indexed toPid
    );

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
        } else {
            // On remote chain. Cross chain pool updates required

            // Mint Zorro on this (remote) chain
            Zorro(ZORRO).mint(address(this), ZORROReward);
            // Get endpoint contract
            address homeChainEndpointContract = endpointContracts[homeChainId];
            // Make cross-chain burn request
            // TODO: Make this a LayerZero request
            // XChainEndpoint(homeChainEndpointContract).sendXChainTransaction(
            //     abi.encodePacked(homeChainZorroController),
            //     abi.encodeWithSignature(
            //         "receiveXChainBurnRewardsRequest(uint256 _amount)",
            //         ZORROReward
            //     ),
            //     ""
            // );
        }
    }

    /// @notice Receives an authorized burn request from another chain and burns the specified amount of ZOR tokens from the public pool
    /// @param _amount The quantity of ZOR tokens to burn
    function receiveXChainBurnRewardsRequest(uint256 _amount)
        external
        onlyXChainEndpoints
    {
        // TODO: Make sure to put the chain ID as an argument and emit an event. It will help to keep track of burns better. 
        Zorro(ZORRO).burn(publicPool, _amount);
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
