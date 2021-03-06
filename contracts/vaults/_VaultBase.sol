// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/IAMMRouter01.sol";

import "../interfaces/IAMMRouter02.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "../libraries/SafeSwap.sol";

import "../interfaces/IVault.sol";

import "../interfaces/IZorroControllerXChain.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

abstract contract VaultBase is IVault, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    /* Libraries */
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using SafeMathUpgradeable for uint256;

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
    // Governance
    address public govAddress; // Timelock controller contract
    bool public onlyGov; // Enforce gov only access on certain functions
    // Key Zorro addresses
    address public zorroControllerAddress; // Address of ZorroController contract
    address public zorroXChainController; // Address of ZorroControllerXChain contract TODO: Constructor/setter
    address public ZORROAddress; // Address of Zorro ERC20 token
    address public zorroStakingVault; // Address of ZOR single staking vault
    // Pool/farm/token IDs/addresses
    address public wantAddress; // Address of contract that represents the staked token (e.g. PancakePair Contract / LP token on Pancakeswap)
    address public token0Address; // Address of first (or only) token
    address public token1Address; // Address of second token in pair if applicable
    address public earnedAddress; // Address of token that rewards are denominated in from farmContractAddress contract (e.g. CAKE token for Pancakeswap)
    address public farmContractAddress; // Address of farm, e.g.: MasterChef (Pancakeswap) or MasterApe (Apeswap) contract
    address public tokenUSDCAddress; // USDC token address
    // Other addresses
    address public burnAddress; // Address to send funds to, to burn them
    address public rewardsAddress; // The TimelockController RewardsDistributor contract
    // Routers/Pools
    address public poolAddress; // Address of LP Pool address (e.g. PancakeV2Pair, AcryptosVault)
    address public uniRouterAddress; // Router contract address for adding/removing liquidity, etc.
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
    address[] public USDCToToken0Path;
    address[] public USDCToToken1Path;
    address[] public token0ToUSDCPath;
    address[] public token1ToUSDCPath;
    address[] public earnedToToken0Path;
    address[] public earnedToToken1Path;
    address[] public earnedToZORROPath;
    address[] public earnedToZORLPPoolOtherTokenPath;
    address[] public earnedToUSDCPath;

    // Price feeds
    AggregatorV3Interface public token0PriceFeed; // Token0 price feed
    AggregatorV3Interface public token1PriceFeed; // Token1 price feed
    AggregatorV3Interface public earnTokenPriceFeed; // Price feed of Earn token
    AggregatorV3Interface public lpPoolOtherTokenPriceFeed; // Price feed of token that is NOT ZOR in liquidity pool
    AggregatorV3Interface public ZORPriceFeed; // Price feed of ZOR token

    /* Structs */

    struct VaultAddresses {
        address govAddress;
        address zorroControllerAddress;
        address ZORROAddress;
        address zorroStakingVault;
        address wantAddress;
        address token0Address;
        address token1Address;
        address earnedAddress;
        address farmContractAddress;
        address rewardsAddress;
        address poolAddress;
        address uniRouterAddress;
        address zorroLPPool;
        address zorroLPPoolOtherToken;
        address tokenUSDCAddress;
    }

    struct VaultFees {
        uint256 controllerFee;
        uint256 buyBackRate;
        uint256 revShareRate;
        uint256 entranceFeeFactor;
        uint256 withdrawFeeFactor;
    }

    struct VaultPriceFeeds {
        address token0PriceFeed;
        address token1PriceFeed;
        address earnTokenPriceFeed;
        address ZORPriceFeed;
        address lpPoolOtherTokenPriceFeed;
    }

    struct ExchangeRates {
        uint256 earn; // Exchange rate of earn token, times 1e12
        uint256 ZOR; // Exchange rate of ZOR token, times 1e12
        uint256 lpPoolOtherToken; // Exchange rate of token paired with ZOR in LP pool
    }

    /* Events */

    event SetSettings(
        uint256 _entranceFeeFactor,
        uint256 _withdrawFeeFactor,
        uint256 _controllerFee,
        uint256 _buyBackRate,
        uint256 _revShareRate
    );
    event SetGov(address _govAddress);
    event SetOnlyGov(bool _onlyGov);
    event SetUniRouterAddress(address _uniRouterAddress);
    event SetRewardsAddress(address _rewardsAddress);
    event Buyback(uint256 indexed _amount);
    event RevShare(uint256 indexed _amount);

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

    function setTokenUSDCAddress(address _tokenUSDCAddress) public onlyOwner {
        tokenUSDCAddress = _tokenUSDCAddress;
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

    function setUniRouterAddress(address _uniRouterAddress) public onlyOwner {
        uniRouterAddress = _uniRouterAddress;
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
        } else {
            revert("unsupported feed idx");
        }
    }

    function setSwapPaths(uint8 _idx, address[] calldata _path)
        public
        onlyOwner
    {
        if (_idx == 0) {
            USDCToToken0Path = _path;
        } else if (_idx == 1) {
            USDCToToken1Path = _path;
        } else if (_idx == 2) {
            token0ToUSDCPath = _path;
        } else if (_idx == 3) {
            token1ToUSDCPath = _path;
        } else if (_idx == 4) {
            earnedToToken0Path = _path;
        } else if (_idx == 5) {
            earnedToToken1Path = _path;
        } else if (_idx == 6) {
            earnedToZORROPath = _path;
        } else if (_idx == 7) {
            earnedToZORLPPoolOtherTokenPath = _path;
        } else if (_idx == 8) {
            earnedToUSDCPath = _path;
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

    /// @notice Gets the swap path in the opposite direction of a trade
    /// @param _path The swap path to be reversed
    /// @return _newPath An reversed path array
    function _reversePath(address[] memory _path)
        internal
        pure
        returns (address[] memory _newPath)
    {
        uint256 _pathLength = _path.length;
        _newPath = new address[](_pathLength);
        for (uint16 i = 0; i < _pathLength; ++i) {
            _newPath[i] = _path[_path.length.sub(1).sub(i)];
        }
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

    /* Performance fees & buyback */

    /// @notice Combines buyback and rev share operations
    /// @param _earnedAmt The amount of Earned tokens (profit)
    /// @param _maxMarketMovementAllowed Slippage tolerance. 950 = 5%, 990 = 1% etc.
    /// @param _rates ExchangeRates struct with realtime rates information for swaps
    /// @return buybackAmt Amount bought back for LP and burn
    /// @return revShareAmt Amount shared with ZOR stakers
    function _buyBackAndRevShare(
        uint256 _earnedAmt,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal virtual returns (uint256 buybackAmt, uint256 revShareAmt) {
        // Calculate buyback amount
        if (buyBackRate > 0) {
            // Calculate the buyback amount via the buyBackRate parameters
            buybackAmt = _earnedAmt.mul(buyBackRate).div(buyBackRateMax);
        }

        // Calculate revshare amount
        if (revShareRate > 0) {
            // Calculate the buyback amount via the buyBackRate parameters
            revShareAmt = _earnedAmt.mul(revShareRate).div(revShareRateMax);
        }

        // Routing: Determine whether on home chain or not
        if (isHomeChain) {
            // If on home chain, perform buyback, revshare locally
            _buybackOnChain(buybackAmt, _maxMarketMovementAllowed, _rates);
            _revShareOnChain(revShareAmt, _maxMarketMovementAllowed, _rates);
        } else {
            // Otherwise, contact controller, to make cross chain call

            // Swap to Earn to USDC and send to zorro controller contract
            _swapEarnedToUSDC(
                buybackAmt.add(revShareAmt),
                zorroControllerAddress,
                _maxMarketMovementAllowed,
                _rates
            );

            // Call distributeEarningsXChain on controller contract
            IZorroControllerXChainEarn(zorroXChainController)
                .sendXChainDistributeEarningsRequest(
                    pid,
                    buybackAmt,
                    revShareAmt,
                    _maxMarketMovementAllowed
                );
        }
    }

    /// @notice distribute controller (performance) fees
    /// @param _earnedAmt The Earned token amount (profits)
    /// @return fee The amount of controller fees collected for the treasury
    function _distributeFees(uint256 _earnedAmt)
        internal
        virtual
        returns (uint256 fee)
    {
        if (_earnedAmt > 0) {
            // If the Earned token amount is > 0, assess a controller fee, if the controller fee is > 0
            if (controllerFee > 0) {
                // Calculate the fee from the controllerFee parameters
                fee = _earnedAmt.mul(controllerFee).div(
                    controllerFeeMax
                );
                // Transfer the fee to the rewards address
                IERC20Upgradeable(earnedAddress).safeTransfer(rewardsAddress, fee);
            }
        }
    }

    /* Abstract methods */

    // Deposits
    function exchangeUSDForWantToken(
        uint256 _amountUSDC,
        uint256 _maxMarketMovementAllowed
    ) public virtual returns (uint256);

    function depositWantToken(address _account, uint256 _wantAmt)
        public
        virtual
        returns (uint256);

    // Withdrawals
    function withdrawWantToken(address _account, uint256 _wantAmt)
        public
        virtual
        returns (uint256);

    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) public virtual returns (uint256);

    // Earnings/compounding
    function earn(uint256 _maxMarketMovementAllowed) public virtual;

    function _buybackOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal virtual;

    function _revShareOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal virtual;

    function _swapEarnedToUSDC(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal virtual;
}
