// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./_VaultBase.sol";

import "../libraries/PriceFeed.sol";

import "./actions/_VaultActionsLiqStakeLP.sol";

import "../interfaces/IAMMRouter02.sol";

import "../interfaces/IAMMFarm.sol";

/// @title Vault base contract for liquid staking + LP strategy
contract VaultBaseLiqStakeLP is VaultBase {
    /* Libraries */
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */
    /// @notice Upgradeable constructor
    /// @param _initValue A VaultAlpacaInit struct containing all init values
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultBaseLiqStakeLPInit memory _initValue
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
        defaultStablecoin = _initValue.keyAddresses.defaultStablecoin;
        liquidStakeToken = _initValue.liquidStakeToken;
        liquidStakingPool = _initValue.liquidStakingPool;

        // Fees
        controllerFee = _initValue.fees.controllerFee;
        buyBackRate = _initValue.fees.buyBackRate;
        revShareRate = _initValue.fees.revShareRate;
        entranceFeeFactor = _initValue.fees.entranceFeeFactor;
        withdrawFeeFactor = _initValue.fees.withdrawFeeFactor;

        // Swap paths
        earnedToZORROPath = _initValue.earnedToZORROPath;
        earnedToToken0Path = _initValue.earnedToToken0Path;
        stablecoinToToken0Path = _initValue.stablecoinToToken0Path;
        earnedToZORLPPoolOtherTokenPath = _initValue
            .earnedToZORLPPoolOtherTokenPath;
        earnedToStablecoinPath = _initValue.earnedToStablecoinPath;
        stablecoinToToken0Path = _initValue.stablecoinToToken0Path;
        stablecoinToZORROPath = _initValue.stablecoinToZORROPath;
        stablecoinToLPPoolOtherTokenPath = _initValue
            .stablecoinToLPPoolOtherTokenPath;
        liquidStakeToToken0Path = _initValue.liquidStakeToToken0Path;
        // Corresponding reverse paths
        token0ToStablecoinPath = VaultActions(vaultActions).reversePath(
            stablecoinToToken0Path
        );
        token0ToLiquidStakePath = VaultActions(vaultActions).reversePath(
            liquidStakeToToken0Path
        );

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
        liquidStakeTokenPriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.liquidStakeTokenPriceFeed
        );

        maxMarketMovementAllowed = _initValue.maxMarketMovementAllowed;

        // Super call
        VaultBase.initialize(_timelockOwner);
    }

    /* Structs */

    struct VaultBaseLiqStakeLPInit {
        uint256 pid;
        bool isHomeChain;
        bool isFarmable;
        VaultActions.VaultAddresses keyAddresses;
        address liquidStakeToken;
        address liquidStakingPool;
        address[] earnedToZORROPath;
        address[] earnedToToken0Path;
        address[] stablecoinToToken0Path;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToStablecoinPath;
        address[] stablecoinToZORROPath;
        address[] stablecoinToLPPoolOtherTokenPath;
        address[] liquidStakeToToken0Path;
        VaultActions.VaultFees fees;
        VaultBaseLiqStakeLPPriceFeeds priceFeeds;
        uint256 maxMarketMovementAllowed;
    }

    struct VaultBaseLiqStakeLPPriceFeeds {
        address token0PriceFeed;
        address earnTokenPriceFeed;
        address ZORPriceFeed;
        address lpPoolOtherTokenPriceFeed;
        address stablecoinPriceFeed;
        address liquidStakeTokenPriceFeed;
    }

    /* State */

    address[] public stablecoinToZORROPath; // Swap path from USD to ZOR (PCS)
    address[] public stablecoinToLPPoolOtherTokenPath; // Swap path from USD to ZOR LP Pool's "other token" (PCS)
    address[] public liquidStakeToToken0Path; // Swap path from sETH to WETH
    address[] public token0ToLiquidStakePath; // Swap path from WETH to sETH
    address public liquidStakeToken; // Synth token for liquid staking (e.g. sETH)
    address public liquidStakingPool; // Liquid staking pool (can sometimes be the same as liquidStakeToken)
    AggregatorV3Interface public liquidStakeTokenPriceFeed; // Price feed for sETH

    /* Setters */

    function setStablecoinSwapPaths(uint8 _idx, address[] calldata _path)
        external
        onlyOwner
    {
        if (_idx == 0) {
            stablecoinToToken0Path = _path;
        } else if (_idx == 1) {
            stablecoinToZORROPath = _path;
        } else if (_idx == 2) {
            stablecoinToLPPoolOtherTokenPath = _path;
        } else {
            revert("unsupported idx swap path");
        }
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _wantAmt amount of underlying token to deposit/stake
    /// @return sharesAdded uint256 Number of shares added
    function depositWantToken(uint256 _wantAmt)
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

        // Increment want token locked qty. NOTE, no farming takes place here, as the lending protocol automatically takes care of it
        wantLockedTotal = wantLockedTotal.add(_wantAmt);

        // Farm the want token if applicable. Otherwise increment want locked
        if (isFarmable) {
            _farm();
        } else {
            wantLockedTotal = wantLockedTotal.add(_wantAmt);
        }
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

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming LP token. Responsible for staking LP token in a MasterChef/MasterApe-like contract
    function _farm() internal {
        // Preflight checks
        require(isFarmable, "!farmable");

        // Calc balance of sETH on this contract
        uint256 _synthBal = IERC20Upgradeable(liquidStakeToken).balanceOf(
            address(this)
        );

        // Approve spending
        IERC20Upgradeable(liquidStakeToken).safeIncreaseAllowance(
            vaultActions,
            _synthBal
        );

        // Swap 1/2 sETH, to ETH and add liquidity to an LP Pool (sends LP token back to this address)
        VaultActionsLiqStakeLP(vaultActions).stakeInLPPool(
            _synthBal,
            VaultActionsLiqStakeLP.StakeLiqTokenInLPPoolParams({
                liquidStakeToken: liquidStakeToken,
                nativeToken: token0Address,
                liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                nativeTokenPriceFeed: token0PriceFeed,
                liquidStakeToNativePath: liquidStakeToToken0Path
            }),
            maxMarketMovementAllowed
        );

        // Get the LP token stored on this contract
        uint256 _lpBal = IERC20Upgradeable(poolAddress).balanceOf(
            address(this)
        );

        // Allow the farm contract (e.g. MasterChef/MasterApe) the ability to transfer up to the Want amount
        IERC20Upgradeable(poolAddress).safeIncreaseAllowance(
            farmContractAddress,
            _lpBal
        );

        // Deposit the Want tokens in the Farm contract for the appropriate pool ID (PID)
        IAMMFarm(farmContractAddress).deposit(pid, _lpBal);
    }

    /// @notice Internal function for unfarming LP token. Responsible for unstaking LP token from MasterChef/MasterApe contracts
    /// @param _lpAmt the amount of LP tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _lpAmt) internal {
        // Withdraw the LP tokens from the Farm contract pool
        IAMMFarm(farmContractAddress).withdraw(pid, _lpAmt);

        // Calc balance
        uint256 _balLPToken = IERC20Upgradeable(poolAddress).balanceOf(
            address(this)
        );

        // Convert LP tokens to sETH + ETH and swap to sETH (want token)
        VaultActionsLiqStakeLP(vaultActions).unStakeFromLPPool(
            _balLPToken,
            VaultActionsLiqStakeLP.UnstakeLiqTokenFromLPPoolParams({
                liquidStakeToken: liquidStakeToken,
                nativeToken: token0Address,
                lpPoolToken: poolAddress,
                liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                nativeTokenPriceFeed: token0PriceFeed,
                nativeToLiquidStakePath: token0ToLiquidStakePath
            }),
            maxMarketMovementAllowed
        );
    }

    /// @notice Performs necessary operations to convert USD into Want token
    /// @param _amountUSD The USD quantity to exchange (must already be deposited)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        // Increase allowance
        IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(
            vaultActions,
            _amountUSD
        );

        // Exchange
        return
            VaultActionsLiqStakeLP(vaultActions).exchangeUSDForWantToken(
                _amountUSD,
                VaultActionsLiqStakeLP.ExchangeUSDForWantParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    liquidStakeToken: liquidStakeToken,
                    liquidStakePool: liquidStakingPool,
                    poolAddress: poolAddress,
                    token0PriceFeed: token0PriceFeed,
                    liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                    stablecoinPriceFeed: stablecoinPriceFeed,
                    stablecoinToToken0Path: stablecoinToToken0Path,
                    liquidStakeToToken0Path: liquidStakeToToken0Path
                }),
                _maxMarketMovementAllowed
            );
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be deposited beforehand)
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return returnedUSD Amount of USD token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    )
        public
        virtual
        override
        onlyZorroController
        whenNotPaused
        returns (uint256 returnedUSD)
    {
        // Allow spending
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            vaultActions,
            _amount
        );

        // Spending
        return
            VaultActionsLiqStakeLP(vaultActions).exchangeWantTokenForUSD(
                _amount,
                VaultActionsLiqStakeLP.ExchangeWantTokenForUSDParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    poolAddress: poolAddress,
                    liquidStakeToken: liquidStakeToken,
                    token0PriceFeed: token0PriceFeed,
                    liquidStakeTokenPriceFeed: liquidStakeTokenPriceFeed,
                    stablecoinPriceFeed: stablecoinPriceFeed,
                    liquidStakeToToken0Path: liquidStakeToToken0Path,
                    token0ToStablecoinPath: token0ToStablecoinPath
                }),
                _maxMarketMovementAllowed
            );
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
        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // Harvest farm tokens
        _unfarm(0);

        // Get the balance of the Earned token on this contract
        uint256 _earnedAmt = IERC20Upgradeable(earnedAddress).balanceOf(
            address(this)
        );

        // Require pending rewards in order to continue
        require(_earnedAmt > 0, "0earn");

        // Create rates struct
        VaultActions.ExchangeRates memory _rates = VaultActions.ExchangeRates({
            earn: earnTokenPriceFeed.getExchangeRate(),
            ZOR: ZORPriceFeed.getExchangeRate(),
            lpPoolOtherToken: lpPoolOtherTokenPriceFeed.getExchangeRate(),
            stablecoin: stablecoinPriceFeed.getExchangeRate()
        });

        // Calc remainder
        uint256 _remainingAmt;

        {
            // Distribute fees
            uint256 _controllerFee = _distributeFees(_earnedAmt);

            // Buyback & rev share
            (uint256 _buybackAmt, uint256 _revShareAmt) = _buyBackAndRevShare(
                _earnedAmt,
                _maxMarketMovementAllowed,
                _rates
            );

            _remainingAmt = _earnedAmt.sub(_controllerFee).sub(_buybackAmt).sub(
                    _revShareAmt
                );
        }

        // Swap Earned token to token0 if token0 is not the Earned token
        if (earnedAddress != token0Address) {
            // Allow spending
            IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
                vaultActions,
                _remainingAmt
            );

            // Swap earned to token0
            VaultActionsLiqStakeLP(vaultActions).safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _remainingAmt,
                    priceToken0: _rates.earn,
                    priceToken1: token0PriceFeed.getExchangeRate(),
                    token0: earnedAddress,
                    token1: token0Address,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: earnedToToken0Path,
                    destination: address(this)
                })
            );
        }

        // Get balance of Token 0
        uint256 _token0Bal = IERC20Upgradeable(token0Address).balanceOf(
            address(this)
        );

        // Provided that token0 is > 0, re-deposit
        if (_token0Bal > 0) {
            // Stake
            _liquidStake(_token0Bal);
            
            // Farm Want token
            _farm();
        }

        // Update last earned block
        lastEarnBlock = block.number;
    }

    /* Abstract functions - must be overriden in child contracts */

    function _liquidStake(uint256 _amount) internal virtual {}

    function _liquidUnstake(uint256 _amount) internal virtual {}
}
