// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./_VaultBase.sol";

import "../libraries/PriceFeed.sol";

import "../interfaces/ApeLending/ICErc20Interface.sol";

import "../interfaces/ApeLending/IRainMaker.sol";

import "../interfaces/ApeLending/IUnitroller.sol";

import "./actions/VaultActionsApeLending.sol";

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
        token0ToStablecoinPath = VaultActions(vaultActions).reversePath(
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
        VaultActions.VaultAddresses keyAddresses;
        uint256 targetBorrowLimit;
        uint256 targetBorrowLimitHysteresis;
        address[] earnedToZORROPath;
        address[] earnedToToken0Path;
        address[] stablecoinToToken0Path;
        address[] earnedToZORLPPoolOtherTokenPath;
        address[] earnedToStablecoinPath;
        address[] stablecoinToZORROPath;
        address[] stablecoinToLPPoolOtherTokenPath;
        VaultActions.VaultFees fees;
        VaultActions.VaultPriceFeeds priceFeeds;
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
            VaultActionsApeLending(vaultActions).exchangeUSDForWantToken(
                _amountUSD,
                VaultActionsApeLending.ExchangeUSDForWantParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    tokenZorroAddress: ZORROAddress,
                    token0PriceFeed: token0PriceFeed,
                    stablecoinPriceFeed: stablecoinPriceFeed,
                    stablecoinToToken0Path: stablecoinToToken0Path,
                    poolAddress: poolAddress
                }),
                _maxMarketMovementAllowed
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
            VaultActionsApeLending(vaultActions).exchangeWantTokenForUSD(
                _amount,
                VaultActionsApeLending.ExchangeWantTokenForUSDParams({
                    token0Address: token0Address,
                    stablecoin: defaultStablecoin,
                    poolAddress: poolAddress,
                    token0PriceFeed: token0PriceFeed,
                    stablecoinPriceFeed: stablecoinPriceFeed,
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

        // Claim any outstanding farm rewards
        IRainMaker(farmContractAddress).claimComp(address(this));

        // Get the balance of the Earned token on this contract
        uint256 _earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        // Require pending rewards in order to continue
        require(_earnedAmt > 0, "0earn");

        // Create rates struct
        VaultActions.ExchangeRates memory _rates = VaultActions.ExchangeRates({
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

        // Swap earn to token0 if token0 is not earn
        if (token0Address != earnedAddress) {
            // Approve spending
            IERC20Upgradeable(earnedAddress).safeIncreaseAllowance(
                vaultActions,
                _earnedAmtNet
            );

            // Swap
            VaultActionsApeLending(vaultActions).safeSwap(
                SafeSwapParams({
                    amountIn: _earnedAmtNet,
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
        // TODO: Can supplyWant and rebalance() somewhow be grouped into _farm()?
        // For symmetry's sake?
        // Re-supply
        _supplyWant();
        // Re-lever
        _rebalance(0);

        // This vault is only for single asset deposits, so farm that token and exit
        // Update the last earn block
        lastEarnBlock = block.number;
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
        (,uint256 _collateralFactor,,,,) = IUnitrollerApeLending(comptrollerAddress).markets(poolAddress);
        return _collateralFactor;
    }
}

contract VaultApeLendingETH is VaultApeLending {}
