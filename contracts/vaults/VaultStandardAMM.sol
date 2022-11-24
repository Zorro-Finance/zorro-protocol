// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "../interfaces/IAMMFarm.sol";

import "./actions/VaultActionsStandardAMM.sol";

import "./_VaultBase.sol";

/// @title VaultStandardAMM: abstract base class for all PancakeSwap style AMM contracts. Maximizes yield in AMM.
contract VaultStandardAMM is VaultBase {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */

    /// @notice Upgradeable constructor
    /// @param _initValue A VaultStandardAMMInit struct with all constructor params
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultStandardAMMInit memory _initValue
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
        uniRouterAddress = _initValue.keyAddresses.uniRouterAddress;
        zorroLPPool = _initValue.keyAddresses.zorroLPPool;
        zorroLPPoolOtherToken = _initValue.keyAddresses.zorroLPPoolOtherToken;
        defaultStablecoin = _initValue.keyAddresses.defaultStablecoin;

        // Fees
        controllerFee = _initValue.fees.controllerFee;
        buyBackRate = _initValue.fees.buyBackRate;
        revShareRate = _initValue.fees.revShareRate;
        entranceFeeFactor = _initValue.fees.entranceFeeFactor;
        withdrawFeeFactor = _initValue.fees.withdrawFeeFactor;

        // Swap paths
        earnedToZORROPath = _initValue.earnedToZORROPath;
        earnedToToken0Path = _initValue.earnedToToken0Path;
        earnedToToken1Path = _initValue.earnedToToken1Path;
        stablecoinToToken0Path = _initValue.stablecoinToToken0Path;
        stablecoinToToken1Path = _initValue.stablecoinToToken1Path;
        earnedToZORLPPoolOtherTokenPath = _initValue
            .earnedToZORLPPoolOtherTokenPath;
        earnedToStablecoinPath = _initValue.earnedToStablecoinPath;
        // Corresponding reverse paths
        token0ToStablecoinPath = VaultActions(vaultActions).reversePath(
            stablecoinToToken0Path
        );
        token1ToStablecoinPath = VaultActions(vaultActions).reversePath(
            stablecoinToToken1Path
        );

        // Price feeds
        token0PriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.token0PriceFeed
        );
        token1PriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.token1PriceFeed
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

    struct VaultStandardAMMInit {
        uint256 pid;
        bool isHomeChain;
        bool isFarmable;
        VaultActions.VaultAddresses keyAddresses;
        address[] earnedToZORROPath;
        address[] earnedToToken0Path;
        address[] earnedToToken1Path;
        address[] stablecoinToToken0Path;
        address[] stablecoinToToken1Path;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToStablecoinPath;
        VaultActions.VaultFees fees;
        VaultActions.VaultPriceFeeds priceFeeds;
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _wantAmt The amount of Want token to deposit (must already be transferred)
    /// @return sharesAdded Number of shares added
    function depositWantToken(uint256 _wantAmt)
        public
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 sharesAdded)
    {
        // Preflight checks
        require(_wantAmt > 0, "want<0");

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
            sharesAdded =
                (_wantAmt * sharesTotal * entranceFeeFactor) /
                (wantLockedTotal * entranceFeeFactorMax);
        }
        // Increment the shares
        sharesTotal = sharesTotal + sharesAdded;

        // Farm the want token if applicable. Otherwise increment want locked
        if (isFarmable) {
            _farm();
        } else {
            wantLockedTotal = wantLockedTotal + _wantAmt;
        }
    }

    /// @notice Performs necessary operations to convert USD into Want token and transfer back to sender
    /// @param _amountUSD The amount of USD to exchange for Want token (must already be deposited on this contract)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        // Approve spending
        IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(
            vaultActions,
            _amountUSD
        );

        // Perform exchange
        return
            VaultActionsStandardAMM(vaultActions).exchangeUSDForWantToken(
                _amountUSD,
                VaultActionsStandardAMM.ExchUSDToWantParams({
                    stablecoin: defaultStablecoin,
                    token0Address: token0Address,
                    token1Address: token1Address,
                    wantAddress: wantAddress,
                    stablecoinPriceFeed: stablecoinPriceFeed,
                    token0PriceFeed: token0PriceFeed,
                    token1PriceFeed: token1PriceFeed,
                    stablecoinToToken0Path: stablecoinToToken0Path,
                    stablecoinToToken1Path: stablecoinToToken1Path
                }),
                _maxMarketMovementAllowed
            );
    }

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
    function _farm() internal {
        require(isFarmable, "!farmable");
        // Get the Want token stored on this contract
        uint256 wantBal = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );
        // Increment the total Want tokens locked into this contract
        wantLockedTotal = wantLockedTotal + wantBal;
        // Allow the farm contract (e.g. MasterChef/MasterApe) the ability to transfer up to the Want amount
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            farmContractAddress,
            wantBal
        );

        // Deposit the Want tokens in the Farm contract for the appropriate pool ID (PID)
        IAMMFarm(farmContractAddress).deposit(pid, wantBal);
    }

    /// @notice Internal function for unfarming Want token. Responsible for unstaking Want token from MasterChef/MasterApe contracts
    /// @param _wantAmt the amount of Want tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _wantAmt) internal {
        // Withdraw the Want tokens from the Farm contract pool
        IAMMFarm(farmContractAddress).withdraw(pid, _wantAmt);
    }

    /// @notice Fully withdraw Want tokens from the Farm contract (100% withdrawals only)
    /// @param _wantAmt The amount of Want token to withdraw
    /// @return sharesRemoved The number of shares removed
    function withdrawWantToken(uint256 _wantAmt)
        public
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 sharesRemoved)
    {
        // Preflight checks
        require(_wantAmt > 0, "negWant");

        // Shares removed is proportional to the % of total Want tokens locked that _wantAmt represents
        sharesRemoved = (_wantAmt * sharesTotal) / wantLockedTotal;
        // Safety: cap the shares to the total number of shares
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        // Decrement the total shares by the sharesRemoved
        sharesTotal = sharesTotal - sharesRemoved;

        // If a withdrawal fee is specified, discount the _wantAmt by the withdrawal fee
        if (withdrawFeeFactor < withdrawFeeFactorMax) {
            _wantAmt = (_wantAmt * withdrawFeeFactor) / withdrawFeeFactorMax;
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
        wantLockedTotal = wantLockedTotal - _wantAmt;

        // Finally, transfer the want amount from this contract, back to the ZorroController contract
        IERC20Upgradeable(wantAddress).safeTransfer(
            zorroControllerAddress,
            _wantAmt
        );
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal, transfers back to sender
    /// @param _amount The Want token quantity to exchange
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of USD token obtained
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
        // Approve spending
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            vaultActions,
            _amount
        );

        // Perform exchange
        return
            VaultActionsStandardAMM(vaultActions).exchangeWantTokenForUSD(
                _amount,
                VaultActionsStandardAMM.ExchWantToUSDParams({
                    token0PriceFeed: token0PriceFeed,
                    token1PriceFeed: token1PriceFeed,
                    stablecoinPriceFeed: stablecoinPriceFeed,
                    token0Address: token0Address,
                    token1Address: token1Address,
                    stablecoin: defaultStablecoin,
                    token0ToStablecoinPath: token0ToStablecoinPath,
                    token1ToStablecoinPath: token1ToStablecoinPath,
                    wantAddress: wantAddress,
                    poolAddress: poolAddress
                }),
                _maxMarketMovementAllowed
            );
    }

    /// @notice The main compounding (earn) function. Reinvests profits since the last earn event.
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    function earn(uint256 _maxMarketMovementAllowed)
        public
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

        // Get the balance of the Earned token on this contract (CAKE, BANANA, etc.)
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

            _remainingAmt = _earnedAmt - _controllerFee - _buybackAmt - _revShareAmt;
        }

        // Allow spending
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            vaultActions,
            _remainingAmt
        );

        // Swap Earned token to token0 if token0 is not the Earned token
        if (earnedAddress != token0Address) {
            VaultActionsStandardAMM(vaultActions).safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _remainingAmt /2,
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

        // Swap Earned token to token1 if token0 is not the Earned token
        if (earnedAddress != token1Address) {
            VaultActionsStandardAMM(vaultActions).safeSwap(
                SafeSwapUni.SafeSwapParams({
                    amountIn: _remainingAmt / 2,
                    priceToken0: _rates.earn,
                    priceToken1: token1PriceFeed.getExchangeRate(),
                    token0: earnedAddress,
                    token1: token1Address,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: earnedToToken1Path,
                    destination: address(this)
                })
            );
        }

        // Get values of tokens 0 and 1
        uint256 token0Amt = IERC20Upgradeable(token0Address).balanceOf(
            address(this)
        );
        uint256 token1Amt = IERC20Upgradeable(token1Address).balanceOf(
            address(this)
        );

        // Provided that token0 and token1 are both > 0, add liquidity
        if (token0Amt > 0 && token1Amt > 0) {
            // Allow spending
            IERC20Upgradeable(token0Address).safeIncreaseAllowance(
                vaultActions,
                token0Amt
            );
            IERC20Upgradeable(token1Address).safeIncreaseAllowance(
                vaultActions,
                token1Amt
            );

            // Add liquidity
            VaultActionsStandardAMM(vaultActions).joinPool(
                token0Address,
                token1Address,
                token0Amt,
                token1Amt,
                _maxMarketMovementAllowed,
                address(this)
            );
        }

        // Update last earned block
        lastEarnBlock = block.number;

        // Farm Want token
        _farm();
    }
}

contract TraderJoe_ZOR_WAVAX is VaultStandardAMM {}

contract TraderJoe_WAVAX_USDC is VaultStandardAMM {}
