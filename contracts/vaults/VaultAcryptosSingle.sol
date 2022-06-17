// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/IAMMFarm.sol";

import "../interfaces/IAcryptosFarm.sol";

import "../interfaces/IAcryptosVault.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./_VaultBase.sol";

import "../interfaces/IBalancerVault.sol";

import "../libraries/PriceFeed.sol";


/// @title Vault contract for Acryptos single token strategies (e.g. for lending)
contract VaultAcryptosSingle is VaultBase {
    /* Libraries */
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapBalancer for IBalancerVault;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */
    /// @notice Upgradeable constructor
    /// @param _initValue A VaultAcryptosSingleInit struct containing all init values
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultAcryptosSingleInit memory _initValue
    ) public initializer {
        // Vault config
        pid = _initValue.pid;
        isHomeChain = _initValue.isHomeChain;
        isFarmable = _initValue.isFarmable;

        // Addresses
        govAddress = _initValue.keyAddresses.govAddress;
        onlyGov = true;
        zorroControllerAddress = _initValue.keyAddresses.zorroControllerAddress;
        zorroXChainController = _initValue.keyAddresses.zorroXChainController;
        ZORROAddress = _initValue.keyAddresses.ZORROAddress;
        zorroStakingVault = _initValue.keyAddresses.zorroStakingVault;
        wantAddress = _initValue.keyAddresses.wantAddress;
        token0Address = _initValue.keyAddresses.token0Address;
        earnedAddress = _initValue.keyAddresses.earnedAddress;
        farmContractAddress = _initValue.keyAddresses.farmContractAddress;
        rewardsAddress = _initValue.keyAddresses.rewardsAddress;
        poolAddress = _initValue.keyAddresses.poolAddress;
        uniRouterAddress = _initValue.keyAddresses.uniRouterAddress;
        zorroLPPool = _initValue.keyAddresses.zorroLPPool;
        zorroLPPoolOtherToken = _initValue.keyAddresses.zorroLPPoolOtherToken;
        tokenUSDCAddress = _initValue.keyAddresses.tokenUSDCAddress;
        tokenBUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
        balancerPool = 0x894ed9026de37afd9cce1e6c0be7d6b510e3ffe5000100000000000000000001;
        balancerVaultAddress = 0xa82f327BBbF0667356D2935C6532d164b06cEced;
        tokenACS = 0x4197C6EF3879a08cD51e5560da5064B773aa1d29;
        balancerACSWeightBasisPoints = 30;
        balancerBUSDWeightBasisPoints = 10;

        // Fees
        controllerFee = _initValue.fees.controllerFee;
        buyBackRate = _initValue.fees.buyBackRate;
        revShareRate = _initValue.fees.revShareRate;
        entranceFeeFactor = _initValue.fees.entranceFeeFactor;
        withdrawFeeFactor = _initValue.fees.withdrawFeeFactor;

        // Swap paths
        earnedToZORROPath = _initValue.earnedToZORROPath;
        earnedToToken0Path = _initValue.earnedToToken0Path;
        USDCToToken0Path = _initValue.USDCToToken0Path;
        earnedToZORLPPoolOtherTokenPath = _initValue
            .earnedToZORLPPoolOtherTokenPath;
        earnedToUSDCPath = _initValue.earnedToUSDCPath;
        BUSDToToken0Path = _initValue.BUSDToToken0Path;
        BUSDToZORROPath = _initValue.BUSDToZORROPath;
        BUSDToLPPoolOtherTokenPath = _initValue.BUSDToLPPoolOtherTokenPath;
        // Corresponding reverse paths
        token0ToUSDCPath = _reversePath(USDCToToken0Path);

        // Price feeds
        token0PriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.token0PriceFeed
        );
        earnTokenPriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.earnTokenPriceFeed
        );
        lpPoolOtherTokenPriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.lpPoolOtherTokenPriceFeed
        );
        ZORPriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.ZORPriceFeed
        );

        // Super call
        VaultBase.initialize(_timelockOwner);
    }

    /* Structs */

    struct VaultAcryptosSingleInit {
        uint256 pid;
        bool isHomeChain;
        bool isFarmable;
        VaultAddresses keyAddresses;
        address[] earnedToZORROPath;
        address[] earnedToToken0Path;
        address[] USDCToToken0Path;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToUSDCPath;
        address[] BUSDToToken0Path;
        address[] BUSDToZORROPath;
        address[] BUSDToLPPoolOtherTokenPath;
        VaultFees fees;
        VaultPriceFeeds priceFeeds;
    }

    /* State */

    uint256 public balancerACSWeightBasisPoints; // Relative weight of ACS token in balancer pool
    uint256 public balancerBUSDWeightBasisPoints; // Relative weight of BUSD token in balancer pool
    address[] public BUSDToToken0Path; // Swap path from BUSD to Token0 (PCS)
    address[] public BUSDToZORROPath; // Swap path from BUSD to ZOR (PCS)
    address[] public BUSDToLPPoolOtherTokenPath; // Swap path from BUSD to ZOR LP Pool's "other token" (PCS)
    address public tokenBUSD;
    address public tokenACS;
    bytes32 public balancerPool; // The Acryptos ACSI.finance pool ID for swapping Earned token to BUSD tokens.
    address public balancerVaultAddress; // Address of Balancer/ACSI.finance Vault for swaps etc.

    /* Setters */

    function setBalancerWeights(uint256 _acsWeight, uint256 _busdWeight)
        external
        onlyOwner
    {
        balancerACSWeightBasisPoints = _acsWeight;
        balancerBUSDWeightBasisPoints = _busdWeight;
    }

    function setBUSDSwapPaths(uint8 _idx, address[] calldata _path)
        external
        onlyOwner
    {
        if (_idx == 0) {
            BUSDToToken0Path = _path;
        } else if (_idx == 1) {
            BUSDToZORROPath = _path;
        } else if (_idx == 2) {
            BUSDToLPPoolOtherTokenPath = _path;
        } else {
            revert("unsupported idx swap path");
        }
    }

    function setBUSD(address _token) external onlyOwner {
        tokenBUSD = _token;
    }

    function setACS(address _token) external onlyOwner {
        tokenACS = _token;
    }

    function setBalancerPool(bytes32 _pool) external onlyOwner {
        balancerPool = _pool;
    }

    function setBalancerVaultAddress(address _vault) external onlyOwner {
        balancerVaultAddress = _vault;
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _account address of user that this deposit is intended for
    /// @param _wantAmt amount of Want token to deposit/stake
    /// @return sharesAdded uint256 Number of shares added
    function depositWantToken(address _account, uint256 _wantAmt)
        public
        virtual
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 sharesAdded)
    {
        // Preflight checks
        require(_wantAmt > 0, "Want token deposit must be > 0");

        // Transfer Want token from sender
        IERC20Upgradeable(wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _wantAmt
        );

        // Set sharesAdded to the Want token amount specified
        sharesAdded = _wantAmt;
        // If the total number of shares and want tokens locked both exceed 0, the shares added is the proportion of Want tokens locked,
        // discounted by the entrance fee
        if (wantLockedTotal > 0 && sharesTotal > 0) {
            sharesAdded = _wantAmt
                .mul(sharesTotal)
                .mul(entranceFeeFactor)
                .div(wantLockedTotal)
                .div(entranceFeeFactorMax);
        }
        // Increment the shares
        sharesTotal = sharesTotal.add(sharesAdded);

        // Farm the want token if applicable. Otherwise increment want locked
        if (isFarmable) {
            _farm();
        } else {
            wantLockedTotal = wantLockedTotal.add(_wantAmt);
        }
    }

    /// @notice Performs necessary operations to convert USDC into Want token
    /// @param _amountUSDC The USDC quantity to exchange (must already be deposited)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSDC,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        // Get balance of deposited USDC
        uint256 _balUSDC = IERC20(tokenUSDCAddress).balanceOf(address(this));
        // Check that USDC was actually deposited
        require(_amountUSDC > 0, "USDC deposit must be > 0");
        require(_amountUSDC <= _balUSDC, "USDC desired exceeded bal");

        // Use price feed to determine exchange rates
        uint256 _token0ExchangeRate = token0PriceFeed.getExchangeRate();

        // Swap USDC for tokens
        // Increase allowance
        IERC20Upgradeable(tokenUSDCAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _amountUSDC
        );
        // Single asset. Swap from USDC directly to Token0
        _safeSwap(
            SafeSwapParams({
                amountIn: _amountUSDC,
                priceToken0: 1e12,
                priceToken1: _token0ExchangeRate,
                token0: tokenUSDCAddress,
                token1: token0Address,
                token0Weight: 0,
                token1Weight: 0,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: USDCToToken0Path,
                destination: address(this)
            })
        );

        // Get new Token0 balance
        uint256 _token0Bal = IERC20Upgradeable(token0Address).balanceOf(
            address(this)
        );

        // Increase allowance
        IERC20Upgradeable(token0Address).safeIncreaseAllowance(poolAddress, _token0Bal);

        // Deposit token to get Want token
        IAcryptosVault(poolAddress).deposit(_token0Bal);

        // Calculate resulting want token balance
        uint256 _wantAmt = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );

        // Transfer back to sender
        IERC20Upgradeable(wantAddress).safeTransfer(
            zorroControllerAddress,
            _wantAmt
        );

        return _wantAmt;
    }

    /// @notice Safely swaps tokens using the most suitable protocol based on token
    /// @param _swapParams SafeSwapParams for swap
    function _safeSwap(SafeSwapParams memory _swapParams) internal {
        if (_swapParams.token0 == tokenACS || _swapParams.token1 == tokenACS) {
            // Allowance
            IERC20Upgradeable(_swapParams.token0).safeIncreaseAllowance(
                balancerVaultAddress,
                _swapParams.amountIn
            );
            // If it's for the Acryptos tokens, swap on ACS Finance (Balancer clone) (Better liquidity for these tokens only)
            IBalancerVault(balancerVaultAddress).safeSwap(
                balancerPool,
                _swapParams
            );
        } else {
            // Allowance
            IERC20Upgradeable(_swapParams.token0).safeIncreaseAllowance(
                uniRouterAddress,
                _swapParams.amountIn
            );
            // Otherwise, swap on normal Pancakeswap (or Uniswap clone) for simplicity & liquidity
            IAMMRouter02(uniRouterAddress).safeSwap(
                _swapParams.amountIn,
                _swapParams.priceToken0,
                _swapParams.priceToken1,
                _swapParams.maxMarketMovementAllowed,
                _swapParams.path,
                _swapParams.destination,
                block.timestamp.add(600)
            );
        }
    }

    /// @notice Public function for farming Want token.
    function farm() public virtual nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
    function _farm() internal virtual {
        require(isFarmable, "!farmable");
        
        // Get the Want token stored on this contract
        uint256 wantAmt = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );
        // Increment the total Want tokens locked into this contract
        wantLockedTotal = wantLockedTotal.add(wantAmt);
        // Allow the farm contract (e.g. MasterChef) the ability to transfer up to the Want amount
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            farmContractAddress,
            wantAmt
        );

        // Deposit the Want tokens in the Farm contract
        IAcryptosFarm(farmContractAddress).deposit(wantAddress, wantAmt);
    }

    /// @notice Internal function for unfarming Want token. Responsible for unstaking Want token from MasterChef/MasterApe contracts
    /// @param _wantAmt the amount of Want tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _wantAmt) internal {
        // Withdraw the Want tokens from the Farm contract
        IAcryptosFarm(farmContractAddress).withdraw(wantAddress, _wantAmt);
    }

    /// @notice Fully withdraw Want tokens from the Farm contract (100% withdrawals only)
    /// @param _account The address of the owner of vault investment
    /// @param _wantAmt The amount of Want token to withdraw
    /// @return sharesRemoved The number of shares removed
    function withdrawWantToken(address _account, uint256 _wantAmt)
        public
        virtual
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 sharesRemoved)
    {
        // Preflight checks
        require(_wantAmt > 0, "want amt <= 0");

        // Shares removed is proportional to the % of total Want tokens locked that _wantAmt represents
        sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal);
        // Safety: cap the shares to the total number of shares
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        // Decrement the total shares by the sharesRemoved
        sharesTotal = sharesTotal.sub(sharesRemoved);

        // If a withdrawal fee is specified, discount the _wantAmt by the withdrawal fee
        if (withdrawFeeFactor < withdrawFeeFactorMax) {
            _wantAmt = _wantAmt.mul(withdrawFeeFactor).div(
                withdrawFeeFactorMax
            );
        }

        // Unfarm Want token if applicable
        if (isFarmable) {
            _unfarm(_wantAmt);
        }

        // Safety: Check balance of this contract's Want tokens held, and cap _wantAmt to that value
        uint256 _wantBal = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );
        if (_wantAmt > _wantBal) {
            _wantAmt = _wantBal;
        }
        // Safety: cap _wantAmt at the total quantity of Want tokens locked
        if (wantLockedTotal < _wantAmt) {
            _wantAmt = wantLockedTotal;
        }

        // Decrement the total Want locked tokens by the _wantAmt
        wantLockedTotal = wantLockedTotal.sub(_wantAmt);

        // Finally, transfer the want amount from this contract, back to the ZorroController contract
        IERC20Upgradeable(wantAddress).safeTransfer(
            zorroControllerAddress,
            _wantAmt
        );
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be deposited beforehand)
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of USDC token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    )
        public
        virtual
        override
        onlyZorroController
        whenNotPaused
        returns (uint256)
    {
        // Preflight checks
        require(_amount > 0, "Want amt must be > 0");

        // Safely transfer Want token from sender
        IERC20Upgradeable(wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Approve
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(poolAddress, _amount);

        // Withdraw Want token to get Token0
        IAcryptosVault(poolAddress).withdraw(_amount);

        // Use price feed to determine exchange rates
        uint256 _token0ExchangeRate = token0PriceFeed.getExchangeRate();

        // Swap Token0 for USDC
        // Get Token0 balance
        uint256 _token0Bal = IERC20Upgradeable(token0Address).balanceOf(
            address(this)
        );
        // Increase allowance
        IERC20Upgradeable(token0Address).safeIncreaseAllowance(
            uniRouterAddress,
            _token0Bal
        );
        // Swap Token0 -> USDC
        _safeSwap(
            SafeSwapParams({
                amountIn: _token0Bal,
                priceToken0: _token0ExchangeRate,
                priceToken1: 1e12,
                token0: token0Address,
                token1: tokenUSDCAddress,
                token0Weight: 0,
                token1Weight: 0,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: token0ToUSDCPath,
                destination: msg.sender
            })
        );

        // Calculate USDC balance
        return IERC20(tokenUSDCAddress).balanceOf(msg.sender);
    }

    /// @notice The main compounding (earn) function. Reinvests profits since the last earn event.
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    function earn(uint256 _maxMarketMovementAllowed)
        public
        virtual
        override
        nonReentrant
        whenNotPaused
    {
        require(isFarmable, "!farmable for earn");

        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // Harvest farm tokens
        _unfarm(0);

        // Get the balance of the Earned token on this contract (ACS, etc.)
        uint256 _earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        // Get exchange rate from price feed
        uint256 _earnTokenExchangeRate = earnTokenPriceFeed.getExchangeRate();
        uint256 _token0ExchangeRate = token0PriceFeed.getExchangeRate();
        uint256 _ZORExchangeRate = ZORPriceFeed.getExchangeRate();
        uint256 _lpPoolOtherTokenExchangeRate = ZORPriceFeed.getExchangeRate();
        // Create rates struct
        ExchangeRates memory _rates = ExchangeRates({
            earn: _earnTokenExchangeRate,
            ZOR: _ZORExchangeRate,
            lpPoolOtherToken: _lpPoolOtherTokenExchangeRate
        });

        // Distribute fees
        uint256 _controllerFee = _distributeFees(_earnedAmt);

        // Buyback & rev share
        (uint256 _buybackAmt, uint256 _revShareAmt) = _buyBackAndRevShare(
            _earnedAmt,
            _maxMarketMovementAllowed,
            _rates
        );

        // Net earned amt
        uint256 _earnedAmtNet = _earnedAmt
            .sub(_controllerFee)
            .sub(_buybackAmt)
            .sub(_revShareAmt);

        // Swap Earn token for single asset token

        // Step 1: Earned to BUSD
        _safeSwap(
            SafeSwapParams({
                amountIn: _earnedAmtNet,
                priceToken0: _earnTokenExchangeRate,
                priceToken1: 1e12,
                token0: earnedAddress,
                token1: tokenBUSD,
                token0Weight: balancerACSWeightBasisPoints,
                token1Weight: balancerBUSDWeightBasisPoints,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: earnedToToken0Path,
                destination: address(this)
            })
        );

        // Step 2: BUSD to Token0
        uint256 _balBUSD = IERC20Upgradeable(tokenBUSD).balanceOf(
            address(this)
        );

        _safeSwap(
            SafeSwapParams({
                amountIn: _balBUSD,
                priceToken0: 1e12,
                priceToken1: _token0ExchangeRate,
                token0: tokenBUSD,
                token1: token0Address,
                token0Weight: 0,
                token1Weight: 0,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: BUSDToToken0Path,
                destination: address(this)
            })
        );

        // Redeposit single asset token to get Want token
        // Get new Token0 balance
        uint256 _token0Bal = IERC20Upgradeable(token0Address).balanceOf(address(this));
        // Allow spending
        IERC20Upgradeable(token0Address).safeIncreaseAllowance(poolAddress, _token0Bal);
        // Deposit token to get Want token
        IAcryptosVault(poolAddress).deposit(_token0Bal);

        // This vault is only for single asset deposits, so farm that token and exit
        // Update the last earn block
        lastEarnBlock = block.number;
        // Farm LP token
        _farm();
    }

    /// @notice Buys back the earned token on-chain, swaps it to add liquidity to the ZOR pool, then burns the associated LP token
    /// @dev Requires funds to be sent to this address before calling. Can be called internally OR by controller
    /// @param _amount The amount of Earn token to buy back
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _rates ExchangeRates struct with realtime rates information for swaps
    function _buybackOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal override {
        // 1. Swap Earned -> BUSD
        address[] memory _dummyEarnedToBUSDPath;
        _safeSwap(
            SafeSwapParams({
                amountIn: _amount,
                priceToken0: _rates.earn,
                priceToken1: 1e12,
                token0: earnedAddress,
                token1: tokenBUSD,
                token0Weight: balancerACSWeightBasisPoints,
                token1Weight: balancerBUSDWeightBasisPoints,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _dummyEarnedToBUSDPath,
                destination: address(this)
            })
        );

        // Get BUSD bal
        uint256 _balBUSD = IERC20Upgradeable(tokenBUSD).balanceOf(
            address(this)
        );

        // 2. Swap 1/2 BUSD -> ZOR
        _safeSwap(
            SafeSwapParams({
                amountIn: _balBUSD.div(2),
                priceToken0: 1e12,
                priceToken1: _rates.ZOR,
                token0: tokenBUSD,
                token1: ZORROAddress,
                token0Weight: 0,
                token1Weight: 0,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: BUSDToZORROPath,
                destination: address(this)
            })
        );

        // 3. Swap 1/2 BUSD -> LP "other token"
        _safeSwap(
            SafeSwapParams({
                amountIn: _balBUSD.div(2),
                priceToken0: 1e12,
                priceToken1: _rates.lpPoolOtherToken,
                token0: tokenBUSD,
                token1: zorroLPPoolOtherToken,
                token0Weight: 0,
                token1Weight: 0,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: BUSDToLPPoolOtherTokenPath,
                destination: address(this)
            })
        );

        // Enter LP pool and send received token to the burn address
        uint256 zorroTokenAmt = IERC20Upgradeable(ZORROAddress).balanceOf(
            address(this)
        );
        uint256 otherTokenAmt = IERC20Upgradeable(zorroLPPoolOtherToken)
            .balanceOf(address(this));
        IERC20Upgradeable(ZORROAddress).safeIncreaseAllowance(
            uniRouterAddress,
            zorroTokenAmt
        );
        IERC20Upgradeable(zorroLPPoolOtherToken).safeIncreaseAllowance(
            uniRouterAddress,
            otherTokenAmt
        );
        IAMMRouter02(uniRouterAddress).addLiquidity(
            ZORROAddress,
            zorroLPPoolOtherToken,
            zorroTokenAmt,
            otherTokenAmt,
            zorroTokenAmt.mul(_maxMarketMovementAllowed).div(1000),
            otherTokenAmt.mul(_maxMarketMovementAllowed).div(1000),
            burnAddress,
            block.timestamp.add(600)
        );
    }

    /// @notice Sends the specified earnings amount as revenue share to ZOR stakers
    /// @param _amount The amount of Earn token to share as revenue with ZOR stakers
    /// @param _maxMarketMovementAllowed Max slippage. 950 = 5%, 990 = 1%, etc.
    /// @param _rates ExchangeRates struct with realtime rates information for swaps
    function _revShareOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal override {
        // Authorize spending beforehand
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _amount
        );

        // Swap Earn to USDC
        // Require two step swap (Balancer + Uni)
        // 1. Balancer: Earn -> BUSD
        address[] memory _dummyPath;
        _safeSwap(
            SafeSwapParams({
                amountIn: _amount,
                priceToken0: _rates.earn,
                priceToken1: 1e12,
                token0: earnedAddress,
                token1: tokenBUSD,
                token0Weight: balancerACSWeightBasisPoints,
                token1Weight: balancerBUSDWeightBasisPoints,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _dummyPath, // Unused
                destination: address(this)
            })
        );
        // 2. Uni: BUSD -> ZOR
        uint256 _balUSDC = IERC20Upgradeable(tokenUSDCAddress).balanceOf(
            address(this)
        );
        // Increase allowance
        IERC20Upgradeable(tokenUSDCAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _balUSDC
        );
        _safeSwap(
            SafeSwapParams({
                amountIn: _balUSDC,
                priceToken0: 1e12,
                priceToken1: _rates.ZOR,
                token0: tokenUSDCAddress,
                token1: ZORROAddress,
                token0Weight: 0,
                token1Weight: 0,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: BUSDToZORROPath,
                destination: zorroStakingVault
            })
        );
    }

    /// @notice Swaps Earn token to USDC and sends to destination specified
    /// @param _earnedAmount Quantity of Earned tokens
    /// @param _destination Address to send swapped USDC to
    /// @param _maxMarketMovementAllowed Slippage factor. 950 = 5%, 990 = 1%, etc.
    /// @param _rates ExchangeRates struct with realtime rates information for swaps
    function _swapEarnedToUSDC(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal override {
        // Swap ACS to BUSD (Balancer)
        _safeSwap(
            SafeSwapParams({
                amountIn: _earnedAmount,
                priceToken0: _rates.earn,
                priceToken1: 1e12,
                token0: earnedAddress,
                token1: tokenBUSD,
                token0Weight: balancerACSWeightBasisPoints,
                token1Weight: balancerBUSDWeightBasisPoints,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: earnedToUSDCPath, // Unused
                destination: address(this)
            })
        );

        // BUSD balance
        uint256 _balBUSD = IERC20Upgradeable(tokenBUSD).balanceOf(
            address(this)
        );

        // Swap path
        address[] memory _path = new address[](2);
        _path[0] = tokenBUSD;
        _path[1] = tokenUSDCAddress;

        // Swap BUSD to USDC (PCS)
        // Increase allowance
        IERC20Upgradeable(tokenBUSD).safeIncreaseAllowance(
            uniRouterAddress,
            _balBUSD
        );
        // Swap
        _safeSwap(
            SafeSwapParams({
                amountIn: _balBUSD,
                priceToken0: 1e12,
                priceToken1: 1e12,
                token0: tokenBUSD,
                token1: tokenUSDCAddress,
                token0Weight: 0,
                token1Weight: 0,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: _path,
                destination: _destination
            })
        );
    }
}
