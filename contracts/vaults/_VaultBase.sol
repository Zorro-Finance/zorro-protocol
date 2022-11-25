// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/Zorro/Vaults/IVault.sol";

import "../interfaces/IZorroControllerXChain.sol";

import "../libraries/SafeSwap.sol";

import "./actions/_VaultActions.sol";

abstract contract VaultBase is
    IVault,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    /* Libraries */
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */
    function initialize(address _timelockOwner) public initializer {
        // Ownable
        __Ownable_init();
        // Transfer ownership
        transferOwnership(_timelockOwner);
        // Other
        burnAddress = 0x000000000000000000000000000000000000dEaD;
    }

    /* Constants */

    // Addresses
    // Fee min/max bounds
    uint256 public constant controllerFeeMax = 10000; // Denominator for controller fee rate
    uint256 public constant controllerFeeUL = 1000; // Upper limit on controller fee rate (10%)
    uint256 public constant buyBackRateMax = 10000; // Denominator for buyback ratio
    uint256 public constant buyBackRateUL = 1000; // Upper limit on buyback rate (10%)
    uint256 public constant revShareRateMax = 10000; // Denominator for revshare ratio
    uint256 public constant revShareRateUL = 1000; // Upper limit on rev share rate (10%)
    uint256 public constant entranceFeeFactorMax = 10000; // Denominator of entrance fee factor
    uint256 public constant entranceFeeFactorLL = 9000; // 10.0% is the max entrance fee settable. LL = "lowerlimit"
    uint256 public constant withdrawFeeFactorMax = 10000; // Denominator of withdrawal fee factor
    uint256 public constant withdrawFeeFactorLL = 9000; // 10.0% is the max entrance fee settable. LL = lowerlimit

    /* State */

    // Vault characteristics
    bool public isHomeChain; // Whether this is deployed on the home chain
    uint256 public pid; // Pid of pool in farmContractAddress (e.g. the LP pool)
    bool public isFarmable; // If true, will farm tokens and autocompound earnings. If false, will stake the token only
    // Governance
    address public govAddress; // Timelock controller contract
    bool public onlyGov; // Enforce gov only access on certain functions
    // Key Zorro addresses
    address public zorroControllerAddress; // Address of ZorroController contract
    address public zorroXChainController; // Address of ZorroControllerXChain contract
    address public ZORROAddress; // Address of Zorro ERC20 token
    address public zorroStakingVault; // Address of ZOR single staking vault
    address public vaultActions; // Address of VaultActions contract TODO: Need setter, constructor etc.
    // Pool/farm/token IDs/addresses
    address public wantAddress; // Address of contract that represents the staked token (e.g. PancakePair Contract / LP token on Pancakeswap)
    address public token0Address; // Address of first (or only) token
    address public token1Address; // Address of second token in pair if applicable
    address public earnedAddress; // Address of token that rewards are denominated in from farmContractAddress contract (e.g. CAKE token for Pancakeswap)
    address public farmContractAddress; // Address of farm, e.g.: MasterChef (Pancakeswap) or MasterApe (Apeswap) contract
    address public defaultStablecoin; // usually USDC token address
    // Other addresses
    address public burnAddress; // Address to send funds to, to burn them
    address public rewardsAddress; // The TimelockController RewardsDistributor contract
    // Routers/Pools
    address public poolAddress; // Address of LP Pool address (e.g. PancakeV2Pair)
    // Zorro LP pool
    address public zorroLPPool; // Main pool for Zorro liquidity
    address public zorroLPPoolOtherToken; // For the dominant LP pool, the token paired with the ZOR token
    // Fees
    // Controller fee - used to fund operations
    uint256 public controllerFee; // Numerator for controller fee rate (100 = 1%)
    // Buyback - used to elevate scarcity of Zorro token
    uint256 public buyBackRate; // Numerator for buyback ratio (100 = 1%)
    // Revenue sharing - used to share rewards with ZOR stakers
    uint256 public revShareRate; // Numerator for revshare ratio (100 = 1%)
    // Entrance fee - goes to pool + prevents front-running
    uint256 public entranceFeeFactor; // 9990 results in a 0.1% deposit fee (1 - 9990/10000)
    // Withdrawal fee - goes to pool
    uint256 public withdrawFeeFactor; // Numerator of withdrawal fee factor
    // Accounting
    uint256 public lastEarnBlock; // Last recorded block for an earn() event
    uint256 public wantLockedTotal; // Total Want tokens locked/staked for this Vault
    uint256 public sharesTotal; // Total shares for this Vault
    // Swap routes
    address[] public stablecoinToToken0Path;
    address[] public stablecoinToToken1Path;
    address[] public token0ToStablecoinPath;
    address[] public token1ToStablecoinPath;
    address[] public earnedToToken0Path;
    address[] public earnedToToken1Path;
    address[] public earnedToZORROPath;
    address[] public earnedToZORLPPoolOtherTokenPath;
    address[] public earnedToStablecoinPath;

    // Price feeds
    AggregatorV3Interface public token0PriceFeed; // Token0 price feed
    AggregatorV3Interface public token1PriceFeed; // Token1 price feed
    AggregatorV3Interface public earnTokenPriceFeed; // Price feed of Earn token
    AggregatorV3Interface public lpPoolOtherTokenPriceFeed; // Price feed of token that is NOT ZOR in liquidity pool
    AggregatorV3Interface public ZORPriceFeed; // Price feed of ZOR token
    AggregatorV3Interface public stablecoinPriceFeed; // Price feed of stablecoin token (e.g. USDC)

    // Other
    uint256 public maxMarketMovementAllowed; // Default slippage param (used when not overriden) // TODO: Setter/constructor

    /* Modifiers */

    modifier onlyAllowGov() {
        require(msg.sender == govAddress, "!gov");
        _;
    }

    modifier onlyZorroController() {
        require(_msgSender() == zorroControllerAddress, "!zorroController");
        _;
    }

    /* Setters */

    function setPid(uint256 _pid) public onlyOwner {
        pid = _pid;
    }

    function setIsFarmable(bool _isFarmable) public onlyOwner {
        isFarmable = _isFarmable;
    }

    function setFarmContractAddress(address _farmContractAddress)
        public
        onlyOwner
    {
        farmContractAddress = _farmContractAddress;
    }

    function setToken0Address(address _token0Address) public onlyOwner {
        token0Address = _token0Address;
    }

    function setToken1Address(address _token1Address) public onlyOwner {
        token1Address = _token1Address;
    }

    function setEarnedAddress(address _earnedAddress) public onlyOwner {
        earnedAddress = _earnedAddress;
    }

    function setDefaultStablecoin(address _defaultStablecoin) public onlyOwner {
        defaultStablecoin = _defaultStablecoin;
    }

    function setRewardsAddress(address _rewardsAddress) public onlyOwner {
        rewardsAddress = _rewardsAddress;
    }

    function setBurnAddress(address _burnAddress) public onlyOwner {
        burnAddress = _burnAddress;
    }

    function setWantAddress(address _wantAddress) public onlyOwner {
        wantAddress = _wantAddress;
    }

    function setPoolAddress(address _poolAddress) public onlyOwner {
        poolAddress = _poolAddress;
    }

    function setZorroLPPoolAddress(address _poolAddress) public onlyOwner {
        zorroLPPool = _poolAddress;
    }

    function setZorroLPPoolOtherToken(address _otherToken) public onlyOwner {
        zorroLPPoolOtherToken = _otherToken;
    }

    function setZorroControllerAddress(address _zorroControllerAddress)
        public
        onlyOwner
    {
        zorroControllerAddress = _zorroControllerAddress;
    }

    function setZorroXChainControllerAddress(address _zorroXChainController)
        public
        onlyOwner
    {
        zorroXChainController = _zorroXChainController;
    }

    function setZorroStakingVault(address _stakingVault) public onlyOwner {
        zorroStakingVault = _stakingVault;
    }

    function setZORROAddress(address _ZORROAddress) public onlyOwner {
        ZORROAddress = _ZORROAddress;
    }

    function setPriceFeed(uint8 _idx, address _priceFeed) public onlyOwner {
        if (_idx == 0) {
            token0PriceFeed = AggregatorV3Interface(_priceFeed);
        } else if (_idx == 1) {
            token1PriceFeed = AggregatorV3Interface(_priceFeed);
        } else if (_idx == 2) {
            earnTokenPriceFeed = AggregatorV3Interface(_priceFeed);
        } else if (_idx == 3) {
            ZORPriceFeed = AggregatorV3Interface(_priceFeed);
        } else if (_idx == 4) {
            lpPoolOtherTokenPriceFeed = AggregatorV3Interface(_priceFeed);
        } else if (_idx == 5) {
            stablecoinPriceFeed = AggregatorV3Interface(_priceFeed);
        } else {
            revert("unsupported feed idx");
        }
    }

    function setSwapPaths(uint8 _idx, address[] calldata _path)
        public
        onlyOwner
    {
        if (_idx == 0) {
            stablecoinToToken0Path = _path;
        } else if (_idx == 1) {
            stablecoinToToken1Path = _path;
        } else if (_idx == 2) {
            token0ToStablecoinPath = _path;
        } else if (_idx == 3) {
            token1ToStablecoinPath = _path;
        } else if (_idx == 4) {
            earnedToToken0Path = _path;
        } else if (_idx == 5) {
            earnedToToken1Path = _path;
        } else if (_idx == 6) {
            earnedToZORROPath = _path;
        } else if (_idx == 7) {
            earnedToZORLPPoolOtherTokenPath = _path;
        } else if (_idx == 8) {
            earnedToStablecoinPath = _path;
        } else {
            revert("unsupported feed idx");
        }
    }

    /// @notice Set governor address
    /// @param _govAddress The new gov address
    function setGov(address _govAddress) public virtual onlyAllowGov {
        govAddress = _govAddress;
        emit SetGov(_govAddress);
    }

    /// @notice Set onlyGov property
    /// @param _onlyGov whether onlyGov should be enforced
    function setOnlyGov(bool _onlyGov) public virtual onlyAllowGov {
        onlyGov = _onlyGov;
        emit SetOnlyGov(_onlyGov);
    }

    /// @notice Configure key fee parameters
    /// @param _entranceFeeFactor Entrance fee numerator (higher means smaller percentage)
    /// @param _withdrawFeeFactor Withdrawal fee numerator (higher means smaller percentage)
    /// @param _controllerFee Controller fee numerator
    /// @param _buyBackRate Buy back rate fee numerator
    /// @param _revShareRate Rev share rate fee numerator
    function setFeeSettings(
        uint256 _entranceFeeFactor,
        uint256 _withdrawFeeFactor,
        uint256 _controllerFee,
        uint256 _buyBackRate,
        uint256 _revShareRate
    ) public virtual onlyAllowGov {
        // Entrance fee
        require(
            _entranceFeeFactor >= entranceFeeFactorLL,
            "_entranceFeeFactor too low"
        );
        require(
            _entranceFeeFactor <= entranceFeeFactorMax,
            "_entranceFeeFactor too high"
        );
        entranceFeeFactor = _entranceFeeFactor;

        // Withdrawal fee
        require(
            _withdrawFeeFactor >= withdrawFeeFactorLL,
            "_withdrawFeeFactor too low"
        );
        require(
            _withdrawFeeFactor <= withdrawFeeFactorMax,
            "_withdrawFeeFactor too high"
        );
        withdrawFeeFactor = _withdrawFeeFactor;

        // Controller (performance) fee
        require(_controllerFee <= controllerFeeUL, "_controllerFee too high");
        controllerFee = _controllerFee;

        // Buyback + LP
        require(_buyBackRate <= buyBackRateUL, "_buyBackRate too high");
        buyBackRate = _buyBackRate;

        // Revshare
        require(_revShareRate <= revShareRateUL, "_revShareRate too high");
        revShareRate = _revShareRate;

        // Emit event with new settings
        emit SetSettings(
            _entranceFeeFactor,
            _withdrawFeeFactor,
            _controllerFee,
            _buyBackRate,
            _revShareRate
        );
    }

    function setMaxMarketMovementAllowed(uint256 _slippageNumerator)
        external
        onlyOwner
    {
        maxMarketMovementAllowed = _slippageNumerator;
    }

    /* Maintenance Functions */

    /// @notice Pause contract
    function pause() public virtual onlyAllowGov {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() public virtual onlyAllowGov {
        _unpause();
    }

    /* Safety Functions */

    /// @notice Safely transfer ERC20 tokens stuck in this contract to a specified address
    /// @param _token Address of the ERC20 token to transfer
    /// @param _amount The amount of the tokens to transfer
    /// @param _to The address to transfer tokens to
    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) public virtual onlyAllowGov {
        require(_token != earnedAddress, "!safe");
        require(_token != wantAddress, "!safe");
        IERC20Upgradeable(_token).safeTransfer(_to, _amount);
    }

    /* Earnings */

    /// @notice The main compounding (earn) function. Reinvests profits since the last earn event.
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    function earn(uint256 _maxMarketMovementAllowed)
        public
        virtual
        nonReentrant
        whenNotPaused
    {
        require(isFarmable, "!farmable");

        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // Harvest farm tokens
        _unfarm(0);

        // Calc earned balance
        uint256 _earnedBal = IERC20Upgradeable(earnedAddress).balanceOf(
            address(this)
        );

        // Only continue if farm tokens were earned
        require(_earnedBal > 0, "0earn");

        // Allow spending
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            vaultActions,
            _earnedBal
        );

        // Perform fee distribution (fees + buyback + revshare)
        // and obtain Want token with remainder
        (
            ,
            uint256 _xChainBuybackAmt,
            uint256 _xChainRevShareAmt
        ) = VaultActions(vaultActions).distributeAndReinvestEarnings(
                _earnedBal,
                _maxMarketMovementAllowed,
                VaultActions.DistributeEarningsParams({
                    earnedAddress: earnedAddress,
                    ZORROAddress: ZORROAddress,
                    rewardsAddress: rewardsAddress,
                    stablecoin: defaultStablecoin,
                    zorroStakingVault: zorroStakingVault,
                    zorroLPPoolOtherToken: zorroLPPoolOtherToken,
                    wantAddress: wantAddress,
                    earnTokenPriceFeed: earnTokenPriceFeed,
                    ZORPriceFeed: ZORPriceFeed,
                    lpPoolOtherTokenPriceFeed: lpPoolOtherTokenPriceFeed,
                    stablecoinPriceFeed: stablecoinPriceFeed,
                    earnedToZORROPath: earnedToZORROPath,
                    earnedToZORLPPoolOtherTokenPath: earnedToZORLPPoolOtherTokenPath,
                    earnedToStablecoinPath: earnedToStablecoinPath,
                    controllerFeeBP: uint16(
                        (controllerFee * 10000) / controllerFeeMax
                    ),
                    buybackBP: uint16((buyBackRate * 10000) / buyBackRateMax),
                    revShareBP: uint16(
                        (revShareRate * 10000) / revShareRateMax
                    ),
                    isHomeChain: isHomeChain
                })
            );

        // Distribute earnings cross chain if applicable
        if (_xChainBuybackAmt > 0 || _xChainRevShareAmt > 0) {
            // Call distributeEarningsXChain on controller contract
            IZorroControllerXChainEarn(zorroXChainController)
                .sendXChainDistributeEarningsRequest(
                    pid, // TODO: Is this the Pool PID or vault PID?
                    _xChainBuybackAmt,
                    _xChainRevShareAmt,
                    _maxMarketMovementAllowed
                );
        }

        // Update last earned block
        lastEarnBlock = block.number;

        // Farm Want token
        _farm();
    }

    /* Abstract methods */

    function _farm() internal virtual;

    function _unfarm(uint256 _wantAmt) internal virtual;
}
