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
    // Fee min/max bounds. NOTE that regardless of the constants here, all fee changes occur through a Timelock
    // contract and governance for added safety and fairness.
    uint256 public constant feeDenominator = 10000; // Denominator for fee ratio calculations
    uint256 public constant controllerFeeUL = 5000; // Upper limit on controller fee rate (50%)
    uint256 public constant buyBackRateUL = 5000; // Upper limit on buyback rate (50%)
    uint256 public constant revShareRateUL = 5000; // Upper limit on rev share rate (50%)
    uint256 public constant entranceFeeFactorLL = 9000; // 10.0% is the max entrance fee settable. LL = "lowerlimit"
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
    mapping(address => mapping(address => address[])) public swapPaths; // Swap paths. Mapping: start address => end address => address array describing swap path
    mapping(address => mapping(address => uint16)) public swapPathLength; // Swap path lengths. Mapping: start address => end address => path length

    // Price feeds
    mapping(address => AggregatorV3Interface) public priceFeeds; // Price feeds. Mapping: token address => price feed address (AggregatorV3Interface implementation)

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

    function setPid(uint256 _pid) external onlyOwner {
        pid = _pid;
    }

    function setIsFarmable(bool _isFarmable) external onlyOwner {
        isFarmable = _isFarmable;
    }

    function setContractAddress(uint16 _index, address _addr)
        external
        onlyOwner
    {
        if (_index == 0) {
            token0Address = _addr;
        } else if (_index == 1) {
            token1Address = _addr;
        } else if (_index == 2) {
            defaultStablecoin = _addr;
        } else if (_index == 3) {
            ZORROAddress = _addr;
        } else if (_index == 4) {
            wantAddress = _addr;
        } else if (_index == 5) {
            poolAddress = _addr;
        } else if (_index == 6) {
            earnedAddress = _addr;
        } else if (_index == 7) {
            farmContractAddress = _addr;
        } else if (_index == 8) {
            rewardsAddress = _addr;
        } else if (_index == 9) {
            burnAddress = _addr;
        } else if (_index == 10) {
            zorroLPPool = _addr;
        } else if (_index == 11) {
            zorroLPPoolOtherToken = _addr;
        } else if (_index == 12) {
            zorroControllerAddress = _addr;
        } else if (_index == 13) {
            zorroXChainController = _addr;
        } else if (_index == 14) {
            zorroStakingVault = _addr;
        } else {
            // Safety: Revert if unrecognized index provided
            revert("urecogContractIdx");
        }
    }

    function setPriceFeed(address _token, address _priceFeedAddress)
        external
        onlyOwner
    {
        _setPriceFeed(_token, _priceFeedAddress);
    }

    function _setPriceFeed(address _token, address _priceFeedAddress) internal {
        priceFeeds[_token] = AggregatorV3Interface(_priceFeedAddress);
    }

    function setSwapPaths(address[] memory _path) external onlyOwner {
        _setSwapPaths(_path);
    }

    function _setSwapPaths(address[] memory _path) internal {
        // Prep
        address _startToken = _path[0];
        address _endToken = _path[_path.length - 1];
        // Set path mapping
        swapPaths[_startToken][_endToken] = _path;

        // Set length
        swapPathLength[_startToken][_endToken] = uint16(_path.length);
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
            _entranceFeeFactor <= feeDenominator,
            "_entranceFeeFactor too high"
        );
        entranceFeeFactor = _entranceFeeFactor;

        // Withdrawal fee
        require(
            _withdrawFeeFactor >= withdrawFeeFactorLL,
            "_withdrawFeeFactor too low"
        );
        require(
            _withdrawFeeFactor <= feeDenominator,
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
                    earnTokenPriceFeed: priceFeeds[earnedAddress],
                    ZORPriceFeed: priceFeeds[ZORROAddress],
                    lpPoolOtherTokenPriceFeed: priceFeeds[
                        zorroLPPoolOtherToken
                    ],
                    stablecoinPriceFeed: priceFeeds[defaultStablecoin],
                    earnedToZORROPath: swapPaths[earnedAddress][ZORROAddress],
                    earnedToZORLPPoolOtherTokenPath: swapPaths[earnedAddress][
                        zorroLPPoolOtherToken
                    ],
                    earnedToStablecoinPath: swapPaths[earnedAddress][
                        defaultStablecoin
                    ],
                    controllerFeeBP: uint16(
                        (controllerFee * 10000) / feeDenominator
                    ),
                    buybackBP: uint16((buyBackRate * 10000) / feeDenominator),
                    revShareBP: uint16((revShareRate * 10000) / feeDenominator),
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
