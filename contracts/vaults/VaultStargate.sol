// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IAMMFarm.sol";

import "../interfaces/IStargateRouter.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./_VaultBase.sol";

import "../interfaces/IBalancerVault.sol";

import "../libraries/PriceFeed.sol";

import "../interfaces/IStargateLPStaking.sol";


/// @title Vault contract for Stargate single token strategies (e.g. for lending bridgeable tokens)
contract VaultStargate is VaultBase {
    /* Libraries */
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
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
    ) public {
        // Vault config
        pid = _initValue.pid;
        isCOREStaking = _initValue.isCOREStaking;
        isSingleAssetDeposit = true;
        isZorroComp = _initValue.isZorroComp;
        isHomeChain = _initValue.isHomeChain;

        // Addresses
        govAddress = _initValue.keyAddresses.govAddress;
        onlyGov = true;
        zorroControllerAddress = _initValue.keyAddresses.zorroControllerAddress;
        ZORROAddress = _initValue.keyAddresses.ZORROAddress;
        zorroStakingVault = _initValue.keyAddresses.zorroStakingVault;
        wantAddress = _initValue.keyAddresses.wantAddress;
        token0Address = _initValue.keyAddresses.token0Address;
        token1Address = _initValue.keyAddresses.token1Address;
        earnedAddress = _initValue.keyAddresses.earnedAddress;
        farmContractAddress = _initValue.keyAddresses.farmContractAddress;
        rewardsAddress = _initValue.keyAddresses.rewardsAddress;
        poolAddress = _initValue.keyAddresses.poolAddress;
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

    struct VaultStargateInit {
        uint256 pid;
        bool isCOREStaking;
        bool isZorroComp;
        bool isHomeChain;
        VaultAddresses keyAddresses;
        address[] earnedToZORROPath;
        address[] earnedToToken0Path;
        address[] USDCToToken0Path;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToUSDCPath;
        VaultFees fees;
        VaultPriceFeeds priceFeeds;
        address tokenSTG;
        uint16 stargatePoolId;
    }

    /* State */
    address public tokenSTG; // Stargate token
    uint16 public stargatePoolId; // Stargate Pool that tokens shall be lent to


    /* Setters */
    function setTokenSTG(address _token) external onlyOwner {
        tokenSTG = _token;
    }

    function setStargatePoolId(uint16 _poolId) external onlyOwner {
        stargatePoolId = _poolId;
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _account address of user that this deposit is intended for
    /// @param _wantAmt amount of Want token to deposit/stake
    /// @return uint256 Number of shares added
    function depositWantToken(address _account, uint256 _wantAmt)
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
        IERC20(wantAddress).safeTransferFrom(
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
        userShares[_account] = userShares[_account].add(sharesAdded);

        if (isZorroComp) {
            // If this contract is meant for Autocompounding, start to farm the staked token
            _farm();
        } else {
            // Otherwise, simply increment the quantity of total Want tokens locked
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
        uint256 _balUSDC = IERC20(tokenUSDCAddress).balanceOf(address(this));
        // Check that USDC was actually deposited
        require(_amountUSDC > 0, "USDC deposit must be > 0");
        require(_amountUSDC <= _balUSDC, "USDC desired exceeded bal");

        // Use price feed to determine exchange rates
        uint256 _token0ExchangeRate = token0PriceFeed.getExchangeRate();

        if (tokenUSDCAddress != token0Address) {
            // Only perform swaps if the token is not USDC

            // Swap USDC for tokens
            // Increase allowance
            IERC20(tokenUSDCAddress).safeIncreaseAllowance(
                uniRouterAddress,
                _amountUSDC
            );
            // Single asset. Swap from USDC directly to Token0
            IAMMRouter02(uniRouterAddress).safeSwap(
                _amountUSDC,
                1e12,
                _token0ExchangeRate,
                _maxMarketMovementAllowed,
                USDCToToken0Path,
                address(this),
                block.timestamp.add(600)
            );
        }


        // Get new Token0 balance
        uint256 _token0Bal = IERC20(token0Address).balanceOf(address(this));

        // Deposit token to get Want token
        IStargateRouter(poolAddress).addLiquidity(
            stargatePoolId,
            _token0Bal,
            address(this)
        );

        // Calculate resulting want token balance
        uint256 _wantAmt = IERC20(wantAddress).balanceOf(address(this));

        // Transfer back to sender
        IERC20(wantAddress).safeTransfer(zorroControllerAddress, _wantAmt);

        return _wantAmt;
    }

    /// @notice Public function for farming Want token.
    function farm() public virtual nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
    function _farm() internal virtual {
        // Farming should only occur if this contract is set for autocompounding
        require(isZorroComp, "!isZorroComp");

        // Get the Want token stored on this contract
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        // Increment the total Want tokens locked into this contract
        wantLockedTotal = wantLockedTotal.add(wantAmt);
        // Allow the farm contract (e.g. MasterChef) the ability to transfer up to the Want amount
        IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, wantAmt);

        // Deposit the Want tokens in the Farm contract
        IStargateLPStaking(farmContractAddress).deposit(stargatePoolId, wantAmt);
    }

    /// @notice Internal function for unfarming Want token. Responsible for unstaking Want token from MasterChef/MasterApe contracts
    /// @param _wantAmt the amount of Want tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _wantAmt) internal virtual {
        // Withdraw the Want tokens from the Farm contract
        IStargateLPStaking(farmContractAddress).deposit(stargatePoolId, _wantAmt);
    }

    /// @notice Fully withdraw Want tokens from the Farm contract (100% withdrawals only)
    /// @param _account The address of the owner of vault investment
    /// @param _wantAmt The amount of Want token to withdraw
    /// @return uint256 The number of shares removed
    function withdrawWantToken(address _account, uint256 _wantAmt)
        public
        virtual
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        // Preflight checks
        require(_wantAmt > 0, "want amt <= 0");

        // Shares removed is proportional to the % of total Want tokens locked that _wantAmt represents
        uint256 sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal);
        // Safety: cap the shares to the total number of shares
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        // Decrement the total shares by the sharesRemoved
        sharesTotal = sharesTotal.sub(sharesRemoved);
        userShares[_account] = userShares[_account].sub(sharesRemoved);

        // If a withdrawal fee is specified, discount the _wantAmt by the withdrawal fee
        if (withdrawFeeFactor < withdrawFeeFactorMax) {
            _wantAmt = _wantAmt.mul(withdrawFeeFactor).div(
                withdrawFeeFactorMax
            );
        }

        // If this contract is designated for auto compounding, unfarm the Want tokens
        if (isZorroComp) {
            _unfarm(_wantAmt);
        }

        // Safety: Check balance of this contract's Want tokens held, and cap _wantAmt to that value
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        if (_wantAmt > wantAmt) {
            _wantAmt = wantAmt;
        }
        // Safety: cap _wantAmt at the total quantity of Want tokens locked
        if (wantLockedTotal < _wantAmt) {
            _wantAmt = wantLockedTotal;
        }

        // Decrement the total Want locked tokens by the _wantAmt
        wantLockedTotal = wantLockedTotal.sub(_wantAmt);

        // Finally, transfer the want amount from this contract, back to the ZorroController contract
        IERC20(wantAddress).safeTransfer(zorroControllerAddress, _wantAmt);

        return sharesRemoved;
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
        IERC20(wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Withdraw Want token to get Token0
        IStargateRouter(poolAddress).instantRedeemLocal(
            stargatePoolId,
            _amount,
            address(this)
        );

        // Use price feed to determine exchange rates
        uint256 _token0ExchangeRate = token0PriceFeed.getExchangeRate();

        // Swap Token0 for USDC
        // Get Token0 balance
        uint256 _token0Bal = IERC20(token0Address).balanceOf(address(this));
        // Increase allowance
        IERC20(token0Address).safeIncreaseAllowance(
            uniRouterAddress,
            _token0Bal
        );

        if (token0Address != tokenUSDCAddress) {
            // Only swap if the token is not USDC

            // Swap Token0 -> USDC
            IAMMRouter02(uniRouterAddress).safeSwap(
                _token0Bal,
                _token0ExchangeRate,
                1e12,
                _maxMarketMovementAllowed,
                token0ToUSDCPath,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Calculate USDC balance
        return IERC20(tokenUSDCAddress).balanceOf(address(this));
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
        // Only to be run if this contract is configured for auto-comnpounding
        require(isZorroComp, "!isZorroComp");
        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // Harvest farm tokens
        _unfarm(0);

        // Get the balance of the Earned token on this contract (ACS, etc.)
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

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

        // Reassign value of earned amount after distributing fees
        earnedAmt = _distributeFees(earnedAmt);
        // Reassign value of earned amount after buying back a certain amount of Zorro, sharing revenue
        earnedAmt = _buyBackAndRevShare(
            earnedAmt,
            _maxMarketMovementAllowed,
            _rates
        );

        // Allow spending
        IERC20(earnedAddress).safeIncreaseAllowance(uniRouterAddress, earnedAmt);

        // Swap Earn token for single asset token (STG -> token0)
        IAMMRouter02(uniRouterAddress).safeSwap(
            earnedAmt,
            _earnTokenExchangeRate,
            _token0ExchangeRate,
            _maxMarketMovementAllowed,
            earnedToToken0Path,
            address(this),
            block.timestamp.add(600)
        );

        // Redeposit single asset token to get Want token
        // Get new Token0 balance
        uint256 _token0Bal = IERC20(token0Address).balanceOf(address(this));
        // Deposit token to get Want token
        IStargateRouter(poolAddress).addLiquidity(
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
        ExchangeRates memory _rates
    ) internal override {
        // Authorize spending beforehand
        IERC20(earnedAddress).safeIncreaseAllowance(uniRouterAddress, _amount);

        // 1. Swap 1/2 Earned -> ZOR
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amount.div(2),
            _rates.earn,
            _rates.ZOR,
            _maxMarketMovementAllowed,
            earnedToZORROPath,
            address(this),
            block.timestamp.add(600)
        );

        // 2. Swap 1/2 Earned -> LP "other token"
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amount.div(2),
            _rates.earn,
            _rates.lpPoolOtherToken,
            _maxMarketMovementAllowed,
            earnedToZORLPPoolOtherTokenPath,
            address(this),
            block.timestamp.add(600)
        );

        // Enter LP pool and send received token to the burn address
        uint256 zorroTokenAmt = IERC20(ZORROAddress).balanceOf(address(this));
        uint256 otherTokenAmt = IERC20(zorroLPPoolOtherToken).balanceOf(
            address(this)
        );
        IERC20(ZORROAddress).safeIncreaseAllowance(
            uniRouterAddress,
            zorroTokenAmt
        );
        IERC20(zorroLPPoolOtherToken).safeIncreaseAllowance(
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
        IERC20(earnedAddress).safeIncreaseAllowance(uniRouterAddress, _amount);

        // Swap Earn to ZOR
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amount,
            _rates.earn,
            _rates.ZOR,
            _maxMarketMovementAllowed,
            earnedToZORROPath,
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
        ExchangeRates memory _rates
    ) internal override {
        // Increase allowance
        IERC20(earnedAddress).safeIncreaseAllowance(uniRouterAddress, _earnedAmount);

        // Swap
        IAMMRouter02(uniRouterAddress).safeSwap(
            _earnedAmount,
            _rates.earn,
            1e12,
            _maxMarketMovementAllowed,
            earnedToUSDCPath,
            _destination,
            block.timestamp.add(600)
        );
    }
}