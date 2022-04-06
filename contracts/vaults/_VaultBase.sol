// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@openzeppelin/contracts/security/Pausable.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IAMMRouter01.sol";

import "../interfaces/IAMMRouter02.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../libraries/SafeSwap.sol";

import "../controllers/ZorroController.sol";

import "../interfaces/IVault.sol";


abstract contract VaultBase is IVault, Ownable, ReentrancyGuard, Pausable {
    /* Libraries */
    using SafeERC20 for IERC20;
    using SafeSwapUni for IAMMRouter02;
    using SafeMath for uint256;

    /* Constants */

    // Addresses
    address public constant burnAddress = 0x000000000000000000000000000000000000dEaD; // Address to send funds to, to burn them
    // Fee min/max bounds
    uint256 public constant controllerFeeMax = 10000; // Denominator for controller fee rate
    uint256 public constant controllerFeeUL = 300; // Upper limit on controller fee rate (3%)
    uint256 public constant buyBackRateMax = 10000; // Denominator for buyback ratio
    uint256 public constant buyBackRateUL = 800; // Upper limit on buyback rate (8%)
    uint256 public constant revShareRateMax = 10000; // Denominator for revshare ratio
    uint256 public constant revShareRateUL = 800; // Upper limit on rev share rate (8%)
    uint256 public constant entranceFeeFactorMax = 10000; // Denominator of entrance fee factor
    uint256 public constant entranceFeeFactorLL = 9900; // 1.0% is the max entrance fee settable. LL = "lowerlimit"
    uint256 public constant withdrawFeeFactorMax = 10000; // Denominator of withdrawal fee factor
    uint256 public constant withdrawFeeFactorLL = 9900; // 1.0% is the max entrance fee settable. LL = lowerlimit

    /* State */

    // Vault characteristics
    bool public isCOREStaking; // If true, is for staking just core token of AMM (e.g. CAKE for Pancakeswap, BANANA for Apeswap, etc.). Set to false for Zorro single staking vault
    bool public isSingleAssetDeposit; // Same asset token (not LP pair). Set to True for pools with single assets (ZOR, CAKE, BANANA, ADA, etc.)
    bool public isZorroComp; // This vault is for compounding. If true, will trigger farming/unfarming on earn events. Set to false for Zorro single staking vault
    bool public isHomeChain; // Whether this is deployed on the home chain
    uint256 public pid; // Pid of pool in farmContractAddress (e.g. the LP pool)
    // Governance
    address public govAddress; // Timelock controller contract
    bool public onlyGov; // Enforce gov only access on certain functions
    // Key Zorro addresses
    address public zorroControllerAddress; // Address of ZorroController contract
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
    uint256 public entranceFeeFactor = 9990; // 9990 results in a 0.1% deposit fee (1 - 9990/10000)
    // Withdrawal fee - goes to pool
    uint256 public withdrawFeeFactor = 10000; // Numerator of withdrawal fee factor
    // Accounting
    uint256 public lastEarnBlock; // Last recorded block for an earn() event
    uint256 public wantLockedTotal; // Total Want tokens locked/staked for this Vault
    uint256 public sharesTotal; // Total shares for this Vault
    mapping(address => uint256) public userShares; // Ledger of shares by user for this pool.
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
        uint256 _buyBackRate
    );
    event SetGov(address _govAddress);
    event SetOnlyGov(bool _onlyGov);
    event SetUniRouterAddress(address _uniRouterAddress);
    event SetRewardsAddress(address _rewardsAddress);

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

    function setSwapPaths(uint8 _idx, address[] calldata _path) public onlyOwner {
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
    function setFeeSettings(
        uint256 _entranceFeeFactor,
        uint256 _withdrawFeeFactor,
        uint256 _controllerFee,
        uint256 _buyBackRate
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

        // Emit event with new settings
        emit SetSettings(
            _entranceFeeFactor,
            _withdrawFeeFactor,
            _controllerFee,
            _buyBackRate
        );
    }

    /// @notice Gets the swap path in the opposite direction of a trade
    /// @param _path The swap path to be reversed
    /// @return An reversed path array
    function _reversePath(address[] memory _path)
        internal
        pure
        returns (address[] memory)
    {
        address[] memory _newPath;
        for (uint16 i = 0; i < _path.length; ++i) {
            _newPath[i] = _path[_path.length.sub(1).sub(i)];
        }
        return _newPath;
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
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /* Performance fees & buyback */

    /// @notice Combines buyback and rev share operations
    /// @param _earnedAmt The amount of Earned tokens (profit)
    /// @param _maxMarketMovementAllowed Slippage tolerance. 950 = 5%, 990 = 1% etc.
    /// @return uint256 the remaining earned token amount after buyback and revshare operations
    /// @param _rates ExchangeRates struct with realtime rates information for swaps
    function _buyBackAndRevShare(
        uint256 _earnedAmt,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal virtual returns (uint256) {
        // Calculate buyback amount
        uint256 _buyBackAmt = 0;
        if (buyBackRate > 0) {
            // Calculate the buyback amount via the buyBackRate parameters
            _buyBackAmt = _earnedAmt.mul(buyBackRate).div(buyBackRateMax);
        }

        // Calculate revshare amount
        uint256 _revShareAmt = 0;
        if (_revShareAmt > 0) {
            // Calculate the buyback amount via the buyBackRate parameters
            _revShareAmt = _earnedAmt.mul(revShareRate).div(revShareRateMax);
        }

        // Routing: Determine whether on home chain or not
        if (isHomeChain) {
            // If on home chain, perform buyback, revshare locally
            _buybackOnChain(_buyBackAmt, _maxMarketMovementAllowed, _rates);
            _revShareOnChain(_revShareAmt, _maxMarketMovementAllowed, _rates);
        } else {
            // Otherwise, contact controller, to make cross chain call
            // Fetch the controller contract that is associated with this Vault
            ZorroController zorroController = ZorroController(
                zorroControllerAddress
            );

            // Swap to Earn to USDC and send to zorro controller contract
            _swapEarnedToUSDC(
                _buyBackAmt.add(_revShareAmt),
                zorroControllerAddress,
                _maxMarketMovementAllowed,
                _rates
            );

            // Call distributeEarningsXChain on controller contract
            zorroController.sendXChainDistributeEarningsRequest(
                pid,
                _buyBackAmt,
                _revShareAmt,
                _maxMarketMovementAllowed
            );
        }

        // Return net earnings
        return (_earnedAmt.sub(_buyBackAmt)).sub(_revShareAmt);
    }

    /// @notice distribute controller (performance) fees
    /// @param _earnedAmt The Earned token amount (profits)
    /// @return The Earned token amount net of distributed fees
    function _distributeFees(uint256 _earnedAmt)
        internal
        virtual
        returns (uint256)
    {
        if (_earnedAmt > 0) {
            // If the Earned token amount is > 0, assess a controller fee, if the controller fee is > 0
            if (controllerFee > 0) {
                // Calculate the fee from the controllerFee parameters
                uint256 fee = _earnedAmt.mul(controllerFee).div(
                    controllerFeeMax
                );
                // Transfer the fee to the rewards address
                IERC20(earnedAddress).safeTransfer(rewardsAddress, fee);
                // Decrement the Earned token amount by the fee
                _earnedAmt = _earnedAmt.sub(fee);
            }
        }

        return _earnedAmt;
    }

    /* Abstract methods */

    // Deposits
    function exchangeUSDForWantToken(
        uint256 _amountUSDC,
        uint256 _maxMarketMovementAllowed
    ) public virtual returns (uint256);

    function depositWantToken(
        address _account,
        uint256 _wantAmt
    ) public virtual returns (uint256);

    // Withdrawals
    function withdrawWantToken(
        address _account,
        uint256 _wantAmt
    ) public virtual returns (uint256);

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
