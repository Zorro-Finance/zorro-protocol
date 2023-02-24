// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/Zorro/Vaults/IVault.sol";

import "../interfaces/Zorro/Controllers/IZorroControllerXChain.sol";

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

    /// @notice default initializer (internal). MUST be called by all child contracts in their initializer
    /// @param _timelockOwner The timelock contract adddress that should be established as owner
    /// @param _initValue: The VaultBaseInit struct that contains base init values
    function _initialize(
        address _timelockOwner,
        VaultBaseInit memory _initValue
    ) internal {
        // Ownable
        __Ownable_init();

        // Transfer ownership
        transferOwnership(_timelockOwner);

        // Vault config
        pid = _initValue.config.pid;
        isHomeChain = _initValue.config.isHomeChain;

        // Addresses
        govAddress = _initValue.keyAddresses.govAddress;
        onlyGov = true;
        zorroControllerAddress = _initValue.keyAddresses.zorroControllerAddress;
        zorroXChainController = _initValue.keyAddresses.zorroXChainController;
        ZORROAddress = _initValue.keyAddresses.ZORROAddress;
        zorroStakingVault = _initValue.keyAddresses.zorroStakingVault;
        wantAddress = _initValue.keyAddresses.wantAddress;
        token0Address = _initValue.keyAddresses.token0Address;
        token1Address = _initValue.keyAddresses.token1Address;
        earnedAddress = _initValue.keyAddresses.earnedAddress;
        farmContractAddress = _initValue.keyAddresses.farmContractAddress;
        treasury = _initValue.keyAddresses.treasury;
        poolAddress = _initValue.keyAddresses.poolAddress;
        zorroLPPool = _initValue.keyAddresses.zorroLPPool;
        zorroLPPoolOtherToken = _initValue.keyAddresses.zorroLPPoolOtherToken;
        defaultStablecoin = _initValue.keyAddresses.defaultStablecoin;
        vaultActions = _initValue.keyAddresses.vaultActions;

        // Fees
        controllerFee = _initValue.fees.controllerFee;
        buyBackRate = _initValue.fees.buyBackRate;
        revShareRate = _initValue.fees.revShareRate;
        entranceFeeFactor = _initValue.fees.entranceFeeFactor;
        withdrawFeeFactor = _initValue.fees.withdrawFeeFactor;

        // Swap paths
        _setSwapPaths(_initValue.swapPaths.earnedToZORROPath);
        _setSwapPaths(_initValue.swapPaths.earnedToToken0Path);
        _setSwapPaths(_initValue.swapPaths.earnedToToken1Path);
        _setSwapPaths(_initValue.swapPaths.stablecoinToToken0Path);
        _setSwapPaths(_initValue.swapPaths.stablecoinToToken1Path);
        _setSwapPaths(_initValue.swapPaths.earnedToZORLPPoolOtherTokenPath);
        _setSwapPaths(_initValue.swapPaths.earnedToStablecoinPath);
        _setSwapPaths(_initValue.swapPaths.stablecoinToZORROPath);
        _setSwapPaths(_initValue.swapPaths.stablecoinToLPPoolOtherTokenPath);
        _setSwapPaths(
            IVaultActions(vaultActions).reversePath(
                _initValue.swapPaths.stablecoinToToken0Path
            )
        );
        _setSwapPaths(
            IVaultActions(vaultActions).reversePath(
                _initValue.swapPaths.stablecoinToToken1Path
            )
        );

        // Price feeds
        _setPriceFeed(token0Address, _initValue.priceFeeds.token0PriceFeed);
        _setPriceFeed(token1Address, _initValue.priceFeeds.token1PriceFeed);
        _setPriceFeed(earnedAddress, _initValue.priceFeeds.earnTokenPriceFeed);
        _setPriceFeed(
            zorroLPPoolOtherToken,
            _initValue.priceFeeds.lpPoolOtherTokenPriceFeed
        );
        _setPriceFeed(ZORROAddress, _initValue.priceFeeds.ZORPriceFeed);
        _setPriceFeed(
            defaultStablecoin,
            _initValue.priceFeeds.stablecoinPriceFeed
        );

        // Other
        burnAddress = 0x000000000000000000000000000000000000dEaD;
        maxMarketMovementAllowed = 985;
        dstGasForEarningsCall = _initValue.dstGasForEarningsCall;
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
    // Governance
    address public govAddress; // Timelock controller contract
    bool public onlyGov; // Enforce gov only access on certain functions
    // Key Zorro addresses
    address public zorroControllerAddress; // Address of ZorroController contract
    address public zorroXChainController; // Address of ZorroControllerXChain contract
    address public ZORROAddress; // Address of Zorro ERC20 token
    address public zorroStakingVault; // Address of ZOR single staking vault
    address public vaultActions; // Address of VaultActions contract
    // Pool/farm/token IDs/addresses
    address public wantAddress; // Address of contract that represents the staked token (e.g. PancakePair Contract / LP token on Pancakeswap)
    address public token0Address; // Address of first (or only) token
    address public token1Address; // Address of second token in pair if applicable
    address public earnedAddress; // Address of token that rewards are denominated in from farmContractAddress contract (e.g. CAKE token for Pancakeswap)
    address public farmContractAddress; // Address of farm, e.g.: MasterChef (Pancakeswap) or MasterApe (Apeswap) contract
    address public defaultStablecoin; // usually USDC token address
    // Other addresses
    address public burnAddress; // Address to send funds to, to burn them
    address public treasury; // The treasury contract address
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
    uint256 public principalDebt; // Last recorded position value, accounting for change in principal (measured in Want token)
    uint256 public profitDebt; // Last harvested profit, representing the accumulated profit taken to date (measured in Want token)
    uint256 public sharesTotal; // Total shares for this Vault
    // Swap routes
    mapping(address => mapping(address => address[])) public swapPaths; // Swap paths. Mapping: start address => end address => address array describing swap path
    mapping(address => mapping(address => uint16)) public swapPathLength; // Swap path lengths. Mapping: start address => end address => path length

    // Price feeds
    mapping(address => AggregatorV3Interface) public priceFeeds; // Price feeds. Mapping: token address => price feed address (AggregatorV3Interface implementation)

    // Other
    uint256 public maxMarketMovementAllowed; // Default slippage param (used when not overriden)
    uint256 public dstGasForEarningsCall; // Gas for cross chain earnings message

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
            treasury = _addr;
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
        } else if (_index == 15) {
            vaultActions = _addr;
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
        // Check to make sure path not empty
        if (_path.length == 0) {
            return;
        }

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

    function setDstGasForEarningsCall(uint256 _amount) external onlyOwner {
        dstGasForEarningsCall = _amount;
    }

    /* Investment Functions */

    /// @notice Receives new deposits from user
    /// @param _wantAmt amount of underlying token to deposit/stake
    /// @return sharesAdded uint256 Number of shares added
    function depositWantToken(uint256 _wantAmt)
        public
        virtual
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 sharesAdded)
    {
        // Preflight checks
        require(_wantAmt > 0, "Want token deposit must be > 0");

        // Hook
        _beforeDeposit();

        // Transfer Want token from sender
        IERC20Upgradeable(wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _wantAmt
        );

        // Set sharesAdded to the Want token amount specified
        sharesAdded = _wantAmt;

        // Calc current want equity
        uint256 _wantEquity = IVaultActions(vaultActions).currentWantEquity(
            address(this)
        );

        // If the total number of shares and want tokens locked both exceed 0, the shares added is the proportion of Want tokens locked,
        // discounted by the entrance fee
        if (_wantEquity > 0 && sharesTotal > 0) {
            sharesAdded =
                (_wantAmt * sharesTotal * entranceFeeFactor) /
                (_wantEquity * feeDenominator);
        }

        // Increment the shares
        sharesTotal += sharesAdded;

        // Increment principal debt to account for cash flow
        principalDebt += _wantAmt;

        // Farm the want token if applicable.
        _farm();

        // Hook
        _afterDeposit();
    }

    /// @notice Fully withdraw Want tokens from the Farm contract (100% withdrawals only)
    /// @param _shares The number of shares to withdraw
    /// @return wantRemoved The amount of Want tokens withdrawn
    function withdrawWantToken(uint256 _shares)
        public
        virtual
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 wantRemoved)
    {
        // Preflight checks
        require(_shares > 0, "negShares");

        // Hook
        _beforeWithdrawal();

        // Calc current want equity
        uint256 _wantEquity = IVaultActions(vaultActions).currentWantEquity(
            address(this)
        );

        // Safety: cap the shares to the total number of shares
        if (_shares > sharesTotal) {
            _shares = sharesTotal;
        }

        // Calculate proportional amount of Want
        uint256 _wantRemovable = (_wantEquity * _shares) / sharesTotal;

        // Decrement the total shares by the sharesRemoved
        sharesTotal -= _shares;

        // Unfarm Want token if applicable
        _unfarm(_wantRemovable);

        // Calculate actual Want unfarmed
        wantRemoved = IERC20Upgradeable(wantAddress).balanceOf(address(this));

        // Collect withdrawal fee and deduct from Want, if applicable
        if (withdrawFeeFactor < feeDenominator) {
            wantRemoved *= withdrawFeeFactor / feeDenominator;
        }

        // Decrement principal debt to account for cash flow
        principalDebt -= wantRemoved;

        // Finally, transfer the want amount from this contract, back to the ZorroController contract
        IERC20Upgradeable(wantAddress).safeTransfer(
            zorroControllerAddress,
            wantRemoved
        );

        // Hook
        _afterWithdrawal();
    }

    /// @notice Executes arbitrary logic before deposit is run
    /// @dev To be optionally overridden
    function _beforeDeposit() internal virtual {}

    /// @notice Executes arbitrary logic after deposit is run
    /// @dev To be optionally overridden
    function _afterDeposit() internal virtual {}

    /// @notice Executes arbitrary logic before withdrawal is run
    /// @dev To be optionally overridden
    function _beforeWithdrawal() internal virtual {}

    /// @notice Executes arbitrary logic after withdrawal is run
    /// @dev To be optionally overridden
    function _afterWithdrawal() internal virtual {}

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
    function earn() public virtual nonReentrant whenNotPaused {
        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // Unfarm to redeem want tokens
        _unfarm(0);

        // Calc want balance after harvesting
        uint256 _wantBal = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );

        // Only continue if harvestable earnings present
        require(_wantBal > 0, "0wantHarvested");

        // Allow spending
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            vaultActions,
            _wantBal
        );

        // Perform fee distribution (fees + buyback + revshare)
        // and obtain Want token with remainder
        (
            ,
            uint256 _xChainBuybackAmt,
            uint256 _xChainRevShareAmt
        ) = IVaultActions(vaultActions).distributeAndReinvestEarnings(
                _wantBal,
                maxMarketMovementAllowed,
                IVaultActions.DistributeEarningsParams({
                    ZORROAddress: ZORROAddress,
                    treasury: treasury,
                    stablecoin: defaultStablecoin,
                    zorroStakingVault: zorroStakingVault,
                    zorroLPPoolOtherToken: zorroLPPoolOtherToken,
                    ZORPriceFeed: priceFeeds[ZORROAddress],
                    lpPoolOtherTokenPriceFeed: priceFeeds[
                        zorroLPPoolOtherToken
                    ],
                    stablecoinPriceFeed: priceFeeds[defaultStablecoin],
                    stablecoinToZORROPath: swapPaths[defaultStablecoin][
                        ZORROAddress
                    ],
                    stablecoinToZORLPPoolOtherTokenPath: swapPaths[
                        defaultStablecoin
                    ][zorroLPPoolOtherToken],
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
            // Approve spending
            IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(
                zorroXChainController,
                _xChainBuybackAmt + _xChainRevShareAmt
            );

            // Call distributeEarningsXChain on controller contract
            IZorroControllerXChainEarn(zorroXChainController)
                .sendXChainDistributeEarningsRequest(
                    _xChainBuybackAmt,
                    _xChainRevShareAmt,
                    maxMarketMovementAllowed,
                    dstGasForEarningsCall
                );
        }

        // Update last earned block
        lastEarnBlock = block.number;

        // Update profit debt to make sure gains are only counted once
        profitDebt = _wantBal;

        // Farm Want token to keep earning
        _farm();
    }

    /// @notice Converts USD to Want token and delivers back to this contract
    /// @param _amountUSD Amount of USD to exchange
    /// @param _maxMarketMovementAllowed Slippage (990 = 1%)
    /// @return wantObtained The amount of Want token returned
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) external virtual returns (uint256 wantObtained) {
        // Approve spending
        IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(
            vaultActions,
            _amountUSD
        );

        // Exchange
        wantObtained = IVaultActions(vaultActions).exchangeUSDForWantToken(
            _amountUSD,
            _maxMarketMovementAllowed
        );
    }

    /// @notice Converts Want token to USD and delivers back to this contract
    /// @param _amount Amount of want to exchange
    /// @param _maxMarketMovementAllowed Slippage (990 = 1%)
    /// @return usdObtained The amount of USD token returned
    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) external virtual returns (uint256 usdObtained) {
        // Approve spending
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            vaultActions,
            _amount
        );

        // Exchange
        usdObtained = IVaultActions(vaultActions).exchangeWantTokenForUSD(
            _amount,
            _maxMarketMovementAllowed
        );
    }

    /* Abstract methods */

    function _farm() internal virtual;

    function _unfarm(uint256 _wantAmt) internal virtual;
}
