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

abstract contract VaultBase is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using SafeSwapUni for IAMMRouter02;
    using SafeMath for uint256;

    /* State */
    // Vault characteristics
    bool public isCOREStaking; // If true, is for staking just core token of AMM (e.g. CAKE for Pancakeswap, BANANA for Apeswap, etc.). Set to false for Zorro single staking vault
    bool public isSingleAssetDeposit; // Same asset token (not LP pair). Set to True for pools with single assets (ZOR, CAKE, BANANA, ADA, etc.)
    bool public isZorroComp; // This vault is for compounding. If true, will trigger farming/unfarming on earn events. Set to false for Zorro single staking vault
    bool public isHomeChain; // Whether this is deployed on the home chain (BSC)
    // Pool/farm/token IDs/addresses
    uint256 public pid; // Pid of pool in farmContractAddress (e.g. the LP pool)
    address public farmContractAddress; // Address of farm, e.g.: MasterChef (Pancakeswap) or MasterApe (Apeswap) contract
    address public wantAddress; // Address of contract that represents the staked token (e.g. PancakePair Contract / LP token on Pancakeswap)
    address public token0Address; // Address of first (or only) token
    address public token1Address; // Address of second token in pair if applicable
    address public earnedAddress; // Address of token that rewards are denominated in from farmContractAddress contract (e.g. CAKE token for Pancakeswap)
    address public tokenUSDCAddress; // USDC token address
    // Zorro LP pool
    address public zorroLPPool; // Main pool for Zorro liquidity
    address public zorroLPPoolToken0; // For the dominant LP pool, the 0th token (usually ZOR)
    address public zorroLPPoolToken1; // For the dominant LP pool, the 1st token
    // Other addresses
    address public burnAddress = 0x000000000000000000000000000000000000dEaD; // Address to send funds to, to burn them
    address public rewardsAddress; // The TimelockController RewardsDistributor contract
    // Routers/Pools
    address public uniRouterAddress; // Router contract address for adding/removing liquidity, etc.
    address public poolAddress; // Address of LP Pool address (e.g. PancakeV2Pair, AcryptosVault)
    // Key Zorro addresses
    address public zorroControllerAddress; // Address of ZorroController contract
    address public ZORROAddress; // Address of Zorro ERC20 token
    address public zorroStakingVault; // Address of ZOR single staking vault
    // Governance
    address public govAddress; // Timelock controller contract
    bool public onlyGov = true; // Enforce gov only access on certain functions
    // Accounting
    uint256 public lastEarnBlock = 0; // Last recorded block for an earn() event
    uint256 public wantLockedTotal = 0; // Total Want tokens locked/staked for this Vault
    uint256 public sharesTotal = 0; // Total shares for this Vault
    mapping(address => uint256) public userShares; // Ledger of shares by user for this pool.
    // Fees
    // Controller fee - used to fund operations
    uint256 public controllerFee = 0; // Numerator for controller fee rate (100 = 1%)
    uint256 public constant controllerFeeMax = 10000; // Denominator for controller fee rate
    uint256 public constant controllerFeeUL = 300; // Upper limit on controller fee rate (3%)
    // Buyback - used to elevate scarcity of Zorro token
    uint256 public buyBackRate = 0; // Numerator for buyback ratio (100 = 1%)
    uint256 public constant buyBackRateMax = 10000; // Denominator for buyback ratio
    uint256 public constant buyBackRateUL = 800; // Upper limit on buyback rate (8%)
    // Revenue sharing - used to share rewards with ZOR stakers
    uint256 public revShareRate = 0; // Numerator for revshare ratio (100 = 1%)
    uint256 public constant revShareRateMax = 10000; // Denominator for revshare ratio
    uint256 public constant revShareRateUL = 800; // Upper limit on rev share rate (8%)
    // Entrance fee - goes to pool + prevents front-running
    uint256 public entranceFeeFactor = 9990; // 9990 results in a 0.1% deposit fee (1 - 9990/10000)
    uint256 public constant entranceFeeFactorMax = 10000; // Denominator of entrance fee factor
    uint256 public constant entranceFeeFactorLL = 9900; // 1.0% is the max entrance fee settable. LL = "lowerlimit"
    // Withdrawal fee - goes to pool
    uint256 public withdrawFeeFactor = 10000; // Numerator of withdrawal fee factor
    uint256 public constant withdrawFeeFactorMax = 10000; // Denominator of withdrawal fee factor
    uint256 public constant withdrawFeeFactorLL = 9900; // 1.0% is the max entrance fee settable. LL = lowerlimit
    // Slippage
    uint256 public slippageFactor = 950; // 950 = 5% default slippage tolerance
    uint256 public constant slippageFactorUL = 995;
    // Swap routes
    address[] public USDCToToken0Path;
    address[] public USDCToToken1Path;
    address[] public token0ToUSDCPath;
    address[] public token1ToUSDCPath;
    address[] public earnedToZORROPath;
    address[] public earnedToToken0Path;
    address[] public earnedToToken1Path;
    address[] public token0ToEarnedPath;
    address[] public token1ToEarnedPath;
    address[] public earnedToZORLPPoolToken0Path;
    address[] public earnedToZORLPPoolToken1Path;
    address[] public USDCToWantPath;
    address[] public WantToUSDCPath;
    address[] public earnedToUSDCPath;
    address[] public USDCToZORROPath;

    // Cross chain
    uint256 public xChainEarningsLockStartBlock; // Lock for cross chain earnings operations (start block). 0 when there is no lock
    uint256 public xChainEarningsLockEndBlock; // Lock for cross chain earnings operations (end block). 0 when there is no lock
    mapping(uint256 => uint256) public lockedXChainEarningsUSDC; // Locked earnings in USDC scheduled for burning. Mapping: block number => amount locked

    /* Events */

    event SetSettings(
        uint256 _entranceFeeFactor,
        uint256 _withdrawFeeFactor,
        uint256 _controllerFee,
        uint256 _buyBackRate,
        uint256 _slippageFactor
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

    function setIsCOREStaking(bool _isCOREStaking) public onlyOwner {
        isCOREStaking = _isCOREStaking;
    }
    function setIsSingleAssetDeposit(bool _isSingleAssetDeposit) public onlyOwner {
        isSingleAssetDeposit = _isSingleAssetDeposit;
    }
    function setIsZorroComp(bool _isZorroComp) public onlyOwner {
        isZorroComp = _isZorroComp;
    }
    function setPid(uint256 _pid) public onlyOwner {
        pid = _pid;
    }
    function setFarmContractAddress(address _farmContractAddress) public onlyOwner {
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
    function setUniRouterAddress(address _uniRouterAddress) public onlyOwner {
        uniRouterAddress = _uniRouterAddress;
    }
    function setPoolAddress(address _poolAddress) public onlyOwner {
        poolAddress = _poolAddress;
    }
    function setZorroControllerAddress(address _zorroControllerAddress) public onlyOwner {
        zorroControllerAddress = _zorroControllerAddress;
    }
    function setZORROAddress(address _ZORROAddress) public onlyOwner {
        ZORROAddress = _ZORROAddress;
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
    /// @param _slippageFactor Slippage factor fee numerator
    function setFeeSettings(
        uint256 _entranceFeeFactor,
        uint256 _withdrawFeeFactor,
        uint256 _controllerFee,
        uint256 _buyBackRate,
        uint256 _slippageFactor
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

        // Slippage tolerance
        require(
            _slippageFactor <= slippageFactorUL,
            "_slippageFactor too high"
        );
        slippageFactor = _slippageFactor;

        // Emit event with new settings
        emit SetSettings(
            _entranceFeeFactor,
            _withdrawFeeFactor,
            _controllerFee,
            _buyBackRate,
            _slippageFactor
        );
    }

    /// @notice Takes an encoded (flattened) array of swap paths along with indexes, to set storage variables for swap paths
    /// @dev ONLY to be called by constructor! NOTE: All paths must be specified (none can be skipped)
    /// @param _swapPaths A flattened array of swap paths for a Uniswap style router. Ordered as: [earnedToZORROPath, earnedToToken0Path, earnedToToken1Path, USDCToToken0Path, USDCToToken1Path, earnedToZORLPPoolToken0Path, earnedToZORLPPoolToken1Path]
    /// @param _swapPathStartIndexes An array of start indexes within _swapPaths to represent the start of a new swap path
    function _unpackSwapPaths(
        address[] memory _swapPaths,
        uint16[] memory _swapPathStartIndexes
    ) internal {
        uint16 _currentIndex = _swapPathStartIndexes[0];
        uint256 _ct = 0;
        for (uint16 i = 0; i < _swapPaths.length; ++i) {
            uint16 _nextIndex = 0;
            if (_ct < _swapPathStartIndexes.length) {
                _nextIndex = _swapPathStartIndexes[_ct.add(1)];
            }
            if (i == 0 || i < _nextIndex) {
                if (_ct == 0) {
                    earnedToZORROPath[i] = _swapPaths[i];
                } else if (_ct == 1) {
                    earnedToToken0Path[i] = _swapPaths[i];
                } else if (_ct == 2) {
                    earnedToToken1Path[i] = _swapPaths[i];
                } else if (_ct == 3) {
                    USDCToToken0Path[i] = _swapPaths[i];
                } else if (_ct == 4) {
                    USDCToToken1Path[i] = _swapPaths[i];
                } else if (_ct == 5) {
                    earnedToZORLPPoolToken0Path[i] = _swapPaths[i];
                } else if (_ct == 6) {
                    earnedToZORLPPoolToken1Path[i] = _swapPaths[i];
                } else if (_ct == 7) {
                    earnedToUSDCPath[i] = _swapPaths[i];
                } else if (_ct == 8) {
                    USDCToZORROPath[i] = _swapPaths[i];
                } else {
                    revert("bad swap paths");
                }
            }
        }
    }

    /// @notice Gets the swap path in the opposite direction of a trade
    /// @param _path The swap path to be reversed
    /// @return An reversed path array
    function _reversePath(address[] memory _path) internal pure returns (address[] memory) {
        address[] memory _newPath;
        for (uint16 i = 0; i < _path.length; ++i) {
            _newPath[i] = _path[_path.length.sub(1).sub(i)];
        }
        return _newPath;
    }

    /* Maintenance Functions */

    /// @notice Converts dust tokens into earned tokens, which will be reinvested on the next earn()
    function convertDustToEarned() public virtual whenNotPaused {
        // Only proceed if the contract is meant for autocompounding and is NOT for single staking (CAKE, BANANA, etc.)
        require(isZorroComp, "!isZorroComp");
        require(!isCOREStaking, "isCOREStaking");

        // Converts token0 dust (if any) to earned tokens
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        if (token0Address != earnedAddress && token0Amt > 0) {
            IERC20(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );

            // Swap all dust tokens to earned tokens
            IAMMRouter02(uniRouterAddress).safeSwap(
                token0Amt,
                slippageFactor,
                token0ToEarnedPath,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Converts token1 dust (if any) to earned tokens
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token1Address != earnedAddress && token1Amt > 0) {
            IERC20(token1Address).safeIncreaseAllowance(
                uniRouterAddress,
                token1Amt
            );

            // Swap all dust tokens to earned tokens
            IAMMRouter02(uniRouterAddress).safeSwap(
                token1Amt,
                slippageFactor,
                token1ToEarnedPath,
                address(this),
                block.timestamp.add(600)
            );
        }
    }

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
    /// @return the remaining earned token amount after buyback and revshare operations
    function _buyBackAndRevShare(uint256 _earnedAmt, uint256 _maxMarketMovementAllowed)
        internal
        virtual
        returns (uint256)
    {
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
            _buybackOnChain(_buyBackAmt, _maxMarketMovementAllowed);
            _revShareOnChain(_revShareAmt, _maxMarketMovementAllowed);
        } else {
            // Otherwise, contact controller, to make cross chain call
            // Fetch the controller contract that is associated with this Vault
            ZorroController zorroController = ZorroController(
                zorroControllerAddress
            );

            // Swap to Earn to USDC and send to zorro controller contract
            _swapEarnedToUSDC(_buyBackAmt.add(_revShareAmt), zorroControllerAddress, _maxMarketMovementAllowed);

            // Call buyBackAndRevShare on controller contract
            zorroController.distributeEarningsXChain(
                pid,
                _buyBackAmt,
                _revShareAmt
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

    function depositWantToken(address _account, uint256 _wantAmt)
        public
        virtual
        returns (uint256);

    // Withdrawals
    function withdrawWantToken(address _account, bool _harvestOnly)
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
        uint256 _maxMarketMovementAllowed
    ) internal virtual;

    function _revShareOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) internal virtual;

    function _swapEarnedToUSDC(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed
    ) internal virtual;
}
