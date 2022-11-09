// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./_VaultBase.sol";

import "../libraries/PriceFeed.sol";

import "./VaultLibrary.sol";

import "../interfaces/ApeLending/ICErc20Interface.sol";

import "../interfaces/ApeLending/IRainMaker.sol";

import "../interfaces/ApeLending/IUnitroller.sol";

import "./VaultLendingLibrary.sol";

/// @title Vault contract for ApeLending leveraged lending strategies
contract VaultApeLending is VaultBase {
    /* Libraries */
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */
    /// @notice Upgradeable constructor
    /// @param _initValue A VaultApeLendingInit struct containing all init values
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultApeLendingInit memory _initValue
    ) public initializer {
        // Vault config
        pid = _initValue.pid;
        isHomeChain = _initValue.isHomeChain;

        // Lending params
        targetBorrowLimit = _initValue.targetBorrowLimit;
        targetBorrowLimitHysteresis = _initValue.targetBorrowLimitHysteresis;

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
        comptrollerAddress = _initValue.comptrollerAddress;

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
        // Corresponding reverse paths
        token0ToStablecoinPath = VaultLibrary.reversePath(
            stablecoinToToken0Path
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

        // Super call
        VaultBase.initialize(_timelockOwner);
    }

    /* Structs */

    struct VaultApeLendingInit {
        uint256 pid;
        bool isHomeChain;
        VaultLibrary.VaultAddresses keyAddresses;
        uint256 targetBorrowLimit;
        uint256 targetBorrowLimitHysteresis;
        address[] earnedToZORROPath;
        address[] earnedToToken0Path;
        address[] stablecoinToToken0Path;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToStablecoinPath;
        address[] stablecoinToZORROPath;
        address[] stablecoinToLPPoolOtherTokenPath;
        VaultLibrary.VaultFees fees;
        VaultLibrary.VaultPriceFeeds priceFeeds;
        address comptrollerAddress;
    }

    /* State */

    address[] public stablecoinToZORROPath; // Swap path from BUSD to ZOR (PCS)
    address[] public stablecoinToLPPoolOtherTokenPath; // Swap path from BUSD to ZOR LP Pool's "other token" (PCS)
    uint256 public targetBorrowLimit; // Max borrow rate % (1e18 = 100%)
    uint256 public targetBorrowLimitHysteresis; // +/- envelope (1% = 1e16)
    address public comptrollerAddress; // Unitroller address

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

    function setTargetBorrowLimit(uint256 _tbl) external onlyOwner {
        targetBorrowLimit = _tbl;
    }

    function setTargetBorrowLimitHysteresis(uint256 _tblh) external onlyOwner {
        targetBorrowLimitHysteresis = _tblh;
    }

    function setComptrollerAddress(address _comptroller) external onlyOwner {
        comptrollerAddress = _comptroller;
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

        // Calc balances
        

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
        if (_wantTokenLockedAdj() > 0 && sharesTotal > 0) {
            sharesAdded = _wantAmt
                .mul(sharesTotal)
                .mul(entranceFeeFactor)
                .div(_wantTokenLockedAdj())
                .div(entranceFeeFactorMax);
        }
        // Increment the shares
        sharesTotal = sharesTotal.add(sharesAdded);

        // Farm (leverage)
        _farm();
    }

    /// @notice Calc want token locked, accounting for leveraged supply/borrow
    /// @return amtLocked The adjusted wantLockedTotal quantity
    function _wantTokenLockedAdj() internal returns (uint256 amtLocked) {
        uint256 _wantBal = IERC20Upgradeable(wantAddress).balanceOf(address(this));
        uint256 _supplyBal = ICErc20Interface(poolAddress).balanceOfUnderlying(address(this));
        uint256 _borrowBal = ICErc20Interface(poolAddress).borrowBalanceCurrent(address(this));
        amtLocked = _wantBal.add(_supplyBal).sub(_borrowBal);
    }

    /// @notice Performs necessary operations to convert USD into Want token
    /// @param _amountUSD The USD quantity to exchange (must already be deposited)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        return
            VaultLibraryApeLending.exchangeUSDForWantToken(
                _amountUSD,
                VaultLibraryApeLending.ExchangeUSDForWantParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    tokenZorroAddress: ZORROAddress,
                    token0PriceFeed: token0PriceFeed,
                    stablecoinPriceFeed: stablecoinPriceFeed,
                    uniRouterAddress: uniRouterAddress,
                    stablecoinToToken0Path: stablecoinToToken0Path,
                    poolAddress: poolAddress
                }),
                _maxMarketMovementAllowed
            );
    }

    // TODO: Consider abstracting all instances of this (in every vault to VaultBase contract)
    /// @notice Safely swaps tokens using the most suitable protocol based on token
    /// @param _swapParams SafeSwapParams for swap
    /// @param _decimals Array of decimals for amount In, amount Out
    function _safeSwap(
        SafeSwapParams memory _swapParams,
        uint8[] memory _decimals
    ) internal {
        VaultLibrary.safeSwap(uniRouterAddress, _swapParams, _decimals);
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
        sharesRemoved = _wantAmt.mul(sharesTotal).div(_wantTokenLockedAdj());
        // Safety: cap the shares to the total number of shares
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        // Decrement the total shares by the sharesRemoved
        sharesTotal = sharesTotal.sub(sharesRemoved);


        // Get balance of underlying on this contract
        uint256 _wantBal = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );

        // If amount to withdraw is gt balance, delever by appropriate amount
        if (_wantAmt > _wantBal) {
            // Delever the incremental amount needed and reassign _wantAmt
            _wantAmt = _withdrawSome(_wantAmt.sub(_wantBal));
            // Add back the existing balance and reassign _wantAmt
            _wantAmt = _wantAmt.add(_wantBal);
        }
        // Recalc balance 
        _wantBal = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );
        // Safety: Cap want amount to new balance (after delevering some), as a last resort
        if (_wantAmt > _wantBal) {
            _wantAmt = _wantBal;
        }


        // If a withdrawal fee is specified, discount the _wantAmt by the withdrawal fee
        if (withdrawFeeFactor < withdrawFeeFactorMax) {
            _wantAmt = _wantAmt.mul(withdrawFeeFactor).div(
                withdrawFeeFactorMax
            );
        }

        // Finally, transfer the want amount from this contract, back to the ZorroController contract
        IERC20Upgradeable(wantAddress).safeTransfer(
            zorroControllerAddress,
            _wantAmt
        );
        
        // Rebalance
        _supplyWant();
        _rebalance(0);
    }

    /// @notice TODO
    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        _rebalance(_amount);
        uint256 _balance = ICErc20Interface(poolAddress).balanceOfUnderlying(
            address(this)
        );
        if (_amount > _balance) _amount = _balance;
        require(
            ICErc20Interface(poolAddress).redeemUnderlying(_amount) == 0,
            "_withdrawSome: redeem failed"
        );
        return _amount;
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal and transfers to sender
    /// @param _amount The Want token quantity to exchange (must be deposited beforehand)
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
        return
            VaultLibraryApeLending.exchangeWantTokenForUSD(
                _amount,
                VaultLibraryApeLending.ExchangeWantTokenForUSDParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    poolAddress: poolAddress,
                    token0PriceFeed: token0PriceFeed,
                    stablecoinPriceFeed: stablecoinPriceFeed,
                    token0ToStablecoinPath: token0ToStablecoinPath,
                    uniRouterAddress: uniRouterAddress
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

        // Claim any outstanding farm rewards
        IRainMaker(farmContractAddress).claimComp(address(this));

        // Get the balance of the Earned token on this contract
        uint256 _earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        // Require pending rewards in order to continue
        require(_earnedAmt > 0, "0earn");

        // Get exchange rate from price feed
        uint256 _token0ExchangeRate = token0PriceFeed.getExchangeRate();

        // Create rates struct
        VaultLibrary.ExchangeRates memory _rates = VaultLibrary.ExchangeRates({
            earn: earnTokenPriceFeed.getExchangeRate(),
            ZOR: ZORPriceFeed.getExchangeRate(),
            lpPoolOtherToken: lpPoolOtherTokenPriceFeed.getExchangeRate(),
            stablecoin: stablecoinPriceFeed.getExchangeRate()
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

        // Get decimal info
        uint8[] memory _decimals0 = new uint8[](2);
        _decimals0[0] = ERC20Upgradeable(earnedAddress).decimals();
        _decimals0[1] = ERC20Upgradeable(defaultStablecoin).decimals();
        uint8[] memory _decimals1 = new uint8[](2);
        _decimals1[0] = _decimals0[1];
        _decimals1[1] = ERC20Upgradeable(token0Address).decimals();

        // Swap earn to token0 if token0 is not earn
        if (token0Address != earnedAddress) {
            _safeSwap(
                SafeSwapParams({
                    amountIn: _earnedAmtNet,
                    priceToken0: _rates.earn,
                    priceToken1: _token0ExchangeRate,
                    token0: earnedAddress,
                    token1: token0Address,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: earnedToToken0Path,
                    destination: address(this)
                }),
                _decimals1
            );
        }

        // Redeposit single asset token to get Want token
        // Get new Token0 balance
        uint256 _token0Bal = IERC20Upgradeable(token0Address).balanceOf(
            address(this)
        );
        // Allow spending
        IERC20Upgradeable(token0Address).safeIncreaseAllowance(
            poolAddress,
            _token0Bal
        );
        // Re-supply
        _supplyWant();
        // Re-lever
        _rebalance(0);

        // This vault is only for single asset deposits, so farm that token and exit
        // Update the last earn block
        lastEarnBlock = block.number;
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
        // Self contained block to limit stack depth
        {
            // Get exchange rate
            uint256 _stablecoinExchangeRate = stablecoinPriceFeed
                .getExchangeRate();

            // Get decimal info
            uint8[] memory _decimals0 = new uint8[](2);
            _decimals0[0] = ERC20Upgradeable(earnedAddress).decimals();
            _decimals0[1] = ERC20Upgradeable(defaultStablecoin).decimals();
            uint8[] memory _decimals1 = new uint8[](2);
            _decimals1[0] = _decimals0[1];
            _decimals1[1] = ERC20Upgradeable(ZORROAddress).decimals();
            uint8[] memory _decimals2 = new uint8[](2);
            _decimals2[0] = _decimals0[1];
            _decimals2[1] = ERC20Upgradeable(zorroLPPoolOtherToken).decimals();

            // 1. Swap Earned -> BUSD
            _safeSwap(
                SafeSwapParams({
                    amountIn: _amount,
                    priceToken0: _rates.earn,
                    priceToken1: _stablecoinExchangeRate,
                    token0: earnedAddress,
                    token1: defaultStablecoin,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: earnedToStablecoinPath,
                    destination: address(this)
                }),
                _decimals0
            );

            // Get BUSD bal
            uint256 _balBUSD = IERC20Upgradeable(defaultStablecoin).balanceOf(
                address(this)
            );

            // 2. Swap 1/2 BUSD -> ZOR
            _safeSwap(
                SafeSwapParams({
                    amountIn: _balBUSD.div(2),
                    priceToken0: _stablecoinExchangeRate,
                    priceToken1: _rates.ZOR,
                    token0: defaultStablecoin,
                    token1: ZORROAddress,
                    maxMarketMovementAllowed: _maxMarketMovementAllowed,
                    path: stablecoinToZORROPath,
                    destination: address(this)
                }),
                _decimals1
            );

            // 3. Swap 1/2 BUSD -> LP "other token"
            if (zorroLPPoolOtherToken != defaultStablecoin) {
                _safeSwap(
                    SafeSwapParams({
                        amountIn: _balBUSD.div(2),
                        priceToken0: _stablecoinExchangeRate,
                        priceToken1: _rates.lpPoolOtherToken,
                        token0: defaultStablecoin,
                        token1: zorroLPPoolOtherToken,
                        maxMarketMovementAllowed: _maxMarketMovementAllowed,
                        path: stablecoinToLPPoolOtherTokenPath,
                        destination: address(this)
                    }),
                    _decimals2
                );
            }
        }

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
        uint8[] memory _decimals0 = new uint8[](2);
        _decimals0[0] = ERC20Upgradeable(earnedAddress).decimals();
        _decimals0[1] = ERC20Upgradeable(defaultStablecoin).decimals();
        // Get decimal info
        uint8[] memory _decimals1 = new uint8[](2);
        _decimals1[0] = _decimals0[1];
        _decimals1[1] = ERC20Upgradeable(ZORROAddress).decimals();

        // Authorize spending beforehand
        IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _amount
        );

        // Swap Earn to USD
        // 1. Router: Earn -> BUSD
        _safeSwap(
            SafeSwapParams({
                amountIn: _amount,
                priceToken0: _rates.earn,
                priceToken1: _rates.stablecoin,
                token0: earnedAddress,
                token1: defaultStablecoin,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: earnedToStablecoinPath,
                destination: address(this)
            }),
            _decimals0
        );
        // 2. Uni: BUSD -> ZOR
        uint256 _balUSD = IERC20Upgradeable(defaultStablecoin).balanceOf(
            address(this)
        );
        // Increase allowance
        IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(
            uniRouterAddress,
            _balUSD
        );
        _safeSwap(
            SafeSwapParams({
                amountIn: _balUSD,
                priceToken0: _rates.stablecoin,
                priceToken1: _rates.ZOR,
                token0: defaultStablecoin,
                token1: ZORROAddress,
                maxMarketMovementAllowed: _maxMarketMovementAllowed,
                path: stablecoinToZORROPath,
                destination: zorroStakingVault
            }),
            _decimals1
        );
    }

    /// @notice Swaps Earn token to USD and sends to destination specified
    /// @param _earnedAmount Quantity of Earned tokens
    /// @param _destination Address to send swapped USD to
    /// @param _maxMarketMovementAllowed Slippage factor. 950 = 5%, 990 = 1%, etc.
    /// @param _rates ExchangeRates struct with realtime rates information for swaps
    function _swapEarnedToUSD(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed,
        VaultLibrary.ExchangeRates memory _rates
    ) internal override {
        VaultLibrary.swapEarnedToUSD(
            _earnedAmount,
            _destination,
            _maxMarketMovementAllowed,
            _rates,
            VaultLibrary.SwapEarnedToUSDParams({
                earnedAddress: earnedAddress,
                stablecoin: defaultStablecoin,
                earnedToStablecoinPath: earnedToStablecoinPath,
                uniRouterAddress: uniRouterAddress,
                stablecoinExchangeRate: _rates.stablecoin
            })
        );
    }

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {
        _farm();
    }

    /// @notice Function for farming want token
    function _farm() internal {
        // Supply the underlying token
        _supplyWant();

        // Leverage up to target leverage (using supply-borrow)
        _rebalance(0);
    }

    /// @notice Supplies underlying token to Pool (vToken contract)
    function _supplyWant() internal whenNotPaused {
        // Get underlying balance
        uint256 _wantBal = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );
        // Allow spending of underlying token by Pool (VToken contract)
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            poolAddress,
            _wantBal
        );
        // Supply underlying token
        ICErc20Interface(poolAddress).mint(_wantBal);
    }

    /// @notice Maintains target leverage amount, within tolerance
    /// @param _withdrawAmt The amount of tokens to deleverage for withdrawal
    function _rebalance(uint256 _withdrawAmt) internal {
        /* Init */

        // Be initial supply balance of underlying.
        uint256 _ox = ICErc20Interface(poolAddress).balanceOfUnderlying(
            address(this)
        );
        // If no supply, nothing to do so exit.
        if (_ox == 0) return;

        // If withdrawal greater than balance of underlying, cap it (account for rounding)
        if (_withdrawAmt >= _ox) _withdrawAmt = _ox.sub(1);
        // Adjusted supply = init supply - amt to withdraw
        uint256 _x = _ox.sub(_withdrawAmt);
        // Calc init borrow balance
        uint256 _y = ICErc20Interface(poolAddress).borrowBalanceCurrent(
            address(this)
        );
        // Get collateral factor from protocol
        uint256 _c = collateralFactor();
        // Target leverage
        uint256 _L = _c.mul(targetBorrowLimit).div(1e18);
        // Current leverage = borrow / supply
        uint256 _currentL = _y.mul(1e18).div(_x);
        // Liquidity (of underlying) available in the pool overall
        uint256 _liquidityAvailable = ICErc20Interface(poolAddress).getCash();

        /* Leverage targeting */

        if (_currentL < _L && _L.sub(_currentL) > targetBorrowLimitHysteresis) {
            // If BELOW leverage target and below hysteresis envelope

            // Calculate incremental amount to borrow:
            // (Target lev % * curr supply - curr borrowed)/(1 - Target lev %)
            uint256 _dy = _L.mul(_x).div(1e18).sub(_y).mul(1e18).div(
                uint256(1e18).sub(_L)
            );

            // Cap incremental borrow to init supply * collateral fact % - curr borrowed
            uint256 _max_dy = _ox.mul(_c).div(1e18).sub(_y);
            if (_dy > _max_dy) _dy = _max_dy;
            // Also cap to max liq available
            if (_dy > _liquidityAvailable) _dy = _liquidityAvailable;

            // Borrow incremental amount
            ICErc20Interface(poolAddress).borrow(_dy);

            // Supply the amount borrowed
            _supplyWant();
        } else {
            // If ABOVE leverage target, iteratively deleverage until within hysteresis envelope
            while (
                _currentL > _L &&
                _currentL.sub(_L) > targetBorrowLimitHysteresis
            ) {
                // Calculate incremental amount to borrow:
                // (Curr borrowed - (Target lev % * Curr supply)) / (1 - Target lev %)
                uint256 _dy = _y.sub(_L.mul(_x).div(1e18)).mul(1e18).div(
                    uint256(1e18).sub(_L)
                );
                // Cap incremental borrow-repay to init supply - (curr borrowed / collateral fact %)
                uint256 _max_dy = _ox.sub(_y.mul(1e18).div(_c));
                if (_dy > _max_dy) _dy = _max_dy;
                // Also cap to max liq available
                if (_dy > _liquidityAvailable) _dy = _liquidityAvailable;

                // Redeem underlying increment. Return val must be 0 (success)
                require(
                    ICErc20Interface(poolAddress).redeemUnderlying(_dy) == 0,
                    "rebal fail"
                );

                // Decrement supply bal by amount repaid
                _ox = _ox.sub(_dy);
                // Cap withdrawal amount to new supply (account for rounding)
                if (_withdrawAmt >= _ox) _withdrawAmt = _ox.sub(1);
                // Adjusted supply decremented by withdrawal amount
                _x = _ox.sub(_withdrawAmt);

                // Cap incremental borrow-repay to total amount borrowed
                if (_dy > _y) _dy = _y;
                // Allow pool to spend underlying
                IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
                    poolAddress,
                    _dy
                );
                // Repay borrowed amount (increment)
                ICErc20Interface(poolAddress).repayBorrow(_dy);
                // Decrement total amount borrowed
                _y = _y.sub(_dy);

                // Update current leverage (borrowed / supplied)
                _currentL = _y.mul(1e18).div(_x);
                // Update current liquidity of underlying pool
                _liquidityAvailable = ICErc20Interface(poolAddress).getCash();
            }
        }
    }

    /// @notice Gets loan collateral factor from lending protocol
    /// @return collFactor The collateral factor %. TODO: Specify denominator (1e18?) Check against consuming logic. 
    function collateralFactor() public view returns (uint256 collFactor) {
        (,uint256 _collateralFactor,,,,) = IUnitroller(comptrollerAddress).markets(poolAddress);
        return _collateralFactor;
    }
}

contract VaultApeLendingETH is VaultApeLending {}
