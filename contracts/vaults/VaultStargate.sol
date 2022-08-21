// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/IAMMFarm.sol";

import "../interfaces/IStargateRouter.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./_VaultBase.sol";

import "../interfaces/IBalancerVault.sol";

import "../libraries/PriceFeed.sol";

import "../interfaces/IStargateLPStaking.sol";

import "./VaultLibrary.sol";


/// @title Vault contract for Stargate single token strategies (e.g. for lending bridgeable tokens)
contract VaultStargate is VaultBase {
    /* Libraries */
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapBalancer for IBalancerVault;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */
    /// @notice Upgradeable constructor
    /// @param _initValue A VaultStargateInit struct containing all init values
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultStargateInit memory _initValue
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
        token1Address = _initValue.keyAddresses.token1Address;
        earnedAddress = _initValue.keyAddresses.earnedAddress;
        farmContractAddress = _initValue.keyAddresses.farmContractAddress;
        rewardsAddress = _initValue.keyAddresses.rewardsAddress;
        poolAddress = _initValue.keyAddresses.poolAddress;
        stargateRouter = _initValue.stargateRouter;
        uniRouterAddress = _initValue.keyAddresses.uniRouterAddress;
        zorroLPPool = _initValue.keyAddresses.zorroLPPool;
        zorroLPPoolOtherToken = _initValue.keyAddresses.zorroLPPoolOtherToken;
        tokenUSDCAddress = _initValue.keyAddresses.tokenUSDCAddress;
        tokenSTG = _initValue.tokenSTG;
        stargatePoolId = _initValue.stargatePoolId;

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

        // Corresponding reverse paths
        token0ToUSDCPath = VaultLibrary.reversePath(USDCToToken0Path);

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
        stablecoinPriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.stablecoinPriceFeed
        );

        // Super call
        VaultBase.initialize(_timelockOwner);
    }

    /* Structs */

    struct VaultStargateInit {
        uint256 pid;
        bool isHomeChain;
        bool isFarmable;
        VaultLibrary.VaultAddresses keyAddresses;
        address[] earnedToZORROPath;
        address[] earnedToToken0Path;
        address[] USDCToToken0Path;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToUSDCPath;
        VaultLibrary.VaultFees fees;
        VaultLibrary.VaultPriceFeeds priceFeeds;
        address tokenSTG;
        address stargateRouter;
        uint16 stargatePoolId;
    }

    /* State */
    address public tokenSTG; // Stargate token
    address public stargateRouter; // Stargate Router for adding/removing liquidity etc.
    uint16 public stargatePoolId; // Stargate Pool that tokens shall be lent to

    /* Setters */
    function setTokenSTG(address _token) external onlyOwner {
        tokenSTG = _token;
    }

    function setStargatePoolId(uint16 _poolId) external onlyOwner {
        stargatePoolId = _poolId;
    }

    function setStargateRouter(address _router) external onlyOwner {
        stargateRouter = _router;
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _wantAmt amount of Want token to deposit/stake
    /// @return uint256 Number of shares added
    function depositWantToken(uint256 _wantAmt)
        public
        virtual
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256)
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
        uint256 sharesAdded = _wantAmt;
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

        return sharesAdded;
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
        uint256 _balUSDC = IERC20Upgradeable(tokenUSDCAddress).balanceOf(
            address(this)
        );
        // Check that USDC was actually deposited
        require(_amountUSDC > 0, "dep<=0");
        require(_amountUSDC <= _balUSDC, "amt>bal");

        // Use price feed to determine exchange rates
        uint256[] memory _priceTokens = new uint256[](2);
        _priceTokens[0] = stablecoinPriceFeed.getExchangeRate();
        _priceTokens[1] = token0PriceFeed.getExchangeRate();

        if (tokenUSDCAddress != token0Address) {
            // Only perform swaps if the token is not USDC

            // Get decimal info
            uint8[] memory _decimals = new uint8[](2);
            _decimals[0] = ERC20Upgradeable(tokenUSDCAddress).decimals();
            _decimals[1] = ERC20Upgradeable(token0Address).decimals();

            // Swap USDC for tokens
            // Increase allowance
            IERC20Upgradeable(tokenUSDCAddress).safeIncreaseAllowance(
                uniRouterAddress,
                _amountUSDC
            );
            // Single asset. Swap from USDC directly to Token0
            IAMMRouter02(uniRouterAddress).safeSwap(
                _amountUSDC,
                _priceTokens,
                _maxMarketMovementAllowed,
                USDCToToken0Path,
                _decimals,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Get new Token0 balance
        uint256 _token0Bal = IERC20Upgradeable(token0Address).balanceOf(
            address(this)
        );

        // Safe approve
        IERC20Upgradeable(token0Address).safeIncreaseAllowance(stargateRouter, _token0Bal);

        // Deposit token to get Want token
        IStargateRouter(stargateRouter).addLiquidity(
            stargatePoolId,
            _token0Bal,
            address(this)
        );

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
        IStargateLPStaking(farmContractAddress).deposit(
            stargatePoolId,
            wantAmt
        );
    }

    /// @notice Internal function for unfarming Want token. Responsible for unstaking Want token from MasterChef/MasterApe contracts
    /// @param _wantAmt the amount of Want tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _wantAmt) internal {
        // Withdraw the Want tokens from the Farm contract
        IStargateLPStaking(farmContractAddress).withdraw(
            stargatePoolId,
            _wantAmt
        );
    }

    /// @notice Fully withdraw Want tokens from the Farm contract (100% withdrawals only)
    /// @param _wantAmt The amount of Want token to withdraw
    /// @return sharesRemoved The number of shares removed
    function withdrawWantToken(uint256 _wantAmt)
        public
        virtual
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 sharesRemoved)
    {
        // Preflight checks
        require(_wantAmt > 0, "negWant");

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
        require(_amount > 0, "negWant");

        // Safely transfer Want token from sender
        IERC20Upgradeable(wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Safe approve
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(stargateRouter, _amount);

        if (token0Address != tokenUSDCAddress) {
            // Withdraw Want token to get Token0
            IStargateRouter(stargateRouter).instantRedeemLocal(
                stargatePoolId,
                _amount,
                address(this)
            );

            // Get Token0 balance
            uint256 _token0Bal = IERC20Upgradeable(token0Address).balanceOf(
                address(this)
            );

            // Only swap if the token is not USDC

            // Use price feed to determine exchange rates
            uint256[] memory _priceTokens = new uint256[](2);
            _priceTokens[0] = token0PriceFeed.getExchangeRate();
            _priceTokens[1] = stablecoinPriceFeed.getExchangeRate();

            // Swap Token0 for USDC

            // Get decimal info
            uint8[] memory _decimals = new uint8[](2);
            _decimals[0] = ERC20Upgradeable(token0Address).decimals();
            _decimals[1] = ERC20Upgradeable(tokenUSDCAddress).decimals();

            // Increase allowance
            IERC20Upgradeable(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                _token0Bal
            );

            // Swap Token0 -> USDC
            IAMMRouter02(uniRouterAddress).safeSwap(
                _token0Bal,
                _priceTokens,
                _maxMarketMovementAllowed,
                token0ToUSDCPath,
                _decimals,
                msg.sender,
                block.timestamp.add(600)
            );
        } else {
            // Withdraw Want token to get Token0
            IStargateRouter(stargateRouter).instantRedeemLocal(
                stargatePoolId,
                _amount,
                msg.sender
            );
        }

        // Calculate USDC balance.
        return IERC20Upgradeable(tokenUSDCAddress).balanceOf(msg.sender);
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
        require(isFarmable, "!farmable");
        
        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // Harvest farm tokens
        _unfarm(0);

        // Get the balance of the Earned token on this contract (ACS, etc.)
        uint256 _earnedAmt = IERC20Upgradeable(earnedAddress).balanceOf(
            address(this)
        );

        // Create rates struct
        VaultLibrary.ExchangeRates memory _rates = VaultLibrary.ExchangeRates({
            earn: earnTokenPriceFeed.getExchangeRate(),
            ZOR: ZORPriceFeed.getExchangeRate(),
            lpPoolOtherToken: lpPoolOtherTokenPriceFeed.getExchangeRate(),
            stablecoin: stablecoinPriceFeed.getExchangeRate()
        });
        // Other rates
        uint256[] memory _priceTokens = new uint256[](2);
        _priceTokens[0] = _rates.earn;
        _priceTokens[1] = token0PriceFeed.getExchangeRate();

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

        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(earnedAddress).decimals();
        _decimals[1] = ERC20Upgradeable(token0Address).decimals();

        // Allow spending
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _earnedAmt
        );

        // Swap Earn token for single asset token (STG -> token0)
        IAMMRouter02(uniRouterAddress).safeSwap(
            _earnedAmtNet,
            _priceTokens,
            _maxMarketMovementAllowed,
            earnedToToken0Path,
            _decimals,
            address(this),
            block.timestamp.add(600)
        );

        // Redeposit single asset token to get Want token
        // Get new Token0 balance
        uint256 _token0Bal = IERC20Upgradeable(token0Address).balanceOf(
            address(this)
        );

        // Safe approve
        IERC20Upgradeable(token0Address).safeIncreaseAllowance(stargateRouter, _token0Bal);

        // Deposit token to get Want token
        IStargateRouter(stargateRouter).addLiquidity(
            stargatePoolId,
            _token0Bal,
            address(this)
        );

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
        VaultLibrary.ExchangeRates memory _rates
    ) internal override {
        // Get decimal info
        uint8[] memory _decimals0 = new uint8[](2);
        _decimals0[0] = ERC20Upgradeable(earnedAddress).decimals();
        _decimals0[1] = ERC20Upgradeable(ZORROAddress).decimals();
        // Get decimal info
        uint8[] memory _decimals1 = new uint8[](2);
        _decimals1[0] = _decimals0[0];
        _decimals1[1] = ERC20Upgradeable(zorroLPPoolOtherToken).decimals();

        // Get exchange rates
        uint256[] memory _priceTokens0 = new uint256[](2);
        _priceTokens0[0] = _rates.earn;
        _priceTokens0[1] = _rates.ZOR;
        uint256[] memory _priceTokens1 = new uint256[](2);
        _priceTokens1[0] = _rates.earn;
        _priceTokens1[1] = _rates.lpPoolOtherToken;

        // Authorize spending beforehand
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _amount
        );

        // 1. Swap 1/2 Earned -> ZOR
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amount.div(2),
            _priceTokens0,
            _maxMarketMovementAllowed,
            earnedToZORROPath,
            _decimals0,
            address(this),
            block.timestamp.add(600)
        );

        // 2. Swap 1/2 Earned -> LP "other token"
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amount.div(2),
            _priceTokens1,
            _maxMarketMovementAllowed,
            earnedToZORLPPoolOtherTokenPath,
            _decimals1,
            address(this),
            block.timestamp.add(600)
        );

        // Add liquidity and burn
        _addLiqAndBurn(_maxMarketMovementAllowed);
    }

    /// @notice Adds liquidity and burns the associated LP token
    /// @param _maxMarketMovementAllowed Slippage factor (990 = 1% etc.)
    function _addLiqAndBurn(uint256 _maxMarketMovementAllowed) internal {
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
        VaultLibrary.ExchangeRates memory _rates
    ) internal override {
        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(earnedAddress).decimals();
        _decimals[1] = ERC20Upgradeable(ZORROAddress).decimals();

        // Get exchange rates
        uint256[] memory _priceTokens = new uint256[](2);
        _priceTokens[0] = _rates.earn;
        _priceTokens[1] = _rates.ZOR;

        // Authorize spending beforehand
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _amount
        );

        // Swap Earn to ZOR
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amount,
            _priceTokens,
            _maxMarketMovementAllowed,
            earnedToZORROPath,
            _decimals,
            zorroStakingVault,
            block.timestamp.add(600)
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
        VaultLibrary.ExchangeRates memory _rates
    ) internal override {
        // Get decimal info
        uint8[] memory _decimals = new uint8[](2);
        _decimals[0] = ERC20Upgradeable(earnedAddress).decimals();
        _decimals[1] = ERC20Upgradeable(tokenUSDCAddress).decimals();

        // Get exchange rates
        uint256[] memory _priceTokens = new uint256[](2);
        _priceTokens[0] = _rates.earn;
        _priceTokens[1] = _rates.stablecoin;

        // Increase allowance
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _earnedAmount
        );

        // Swap
        IAMMRouter02(uniRouterAddress).safeSwap(
            _earnedAmount,
            _priceTokens,
            _maxMarketMovementAllowed,
            earnedToUSDCPath,
            _decimals,
            _destination,
            block.timestamp.add(600)
        );
    }
}
