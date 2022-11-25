// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/Lending/ILendingToken.sol";

import "../interfaces/Benqi/IQiTokenSaleDistributor.sol";

import "../interfaces/Benqi/IUnitroller.sol";

import "../interfaces/Zorro/Vaults/IVaultLending.sol";

import "./actions/VaultActionsBenqiLending.sol";

import "./_VaultBase.sol";

/// @title Vault base contract for leveraged lending strategies
abstract contract VaultLending is IVaultLending, VaultBase {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */

    /// @notice Upgradeable constructor
    /// @param _initValue A VaultAlpacaInit struct containing all init values
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultLendingInit memory _initValue
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

    /* State */

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
                (wantLockedTotal * entranceFeeFactor);
        }
        // Increment the shares
        sharesTotal = sharesTotal + sharesAdded;

        // Farm (leverage)
        _farm();
    }

    /// @notice Performs necessary operations to convert USD into Want token
    /// @param _amountUSD The USD quantity to exchange (must already be deposited)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return uint256 Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSD,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        // Allow spending
        IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(
            vaultActions,
            _amountUSD
        );

        // Exchange
        return
            VaultActionsLending(vaultActions).exchangeUSDForWantToken(
                _amountUSD,
                VaultActionsLending.ExchangeUSDForWantParams({
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
        sharesRemoved = (_wantAmt * sharesTotal) / this.wantTokenLockedAdj();
        // Safety: cap the shares to the total number of shares
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        // Decrement the total shares by the sharesRemoved
        sharesTotal = sharesTotal - sharesRemoved;

        // Get balance of underlying on this contract
        uint256 _wantBal = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );

        // If amount to withdraw is gt balance, delever by appropriate amount
        if (_wantAmt > _wantBal) {
            // Delever the incremental amount needed and reassign _wantAmt
            _withdrawSome(_wantAmt - _wantBal);
        }

        // Recalc balance
        _wantBal = IERC20Upgradeable(wantAddress).balanceOf(address(this));

        // Safety: Cap want amount to new balance (after delevering some), as a last resort
        if (_wantAmt > _wantBal) {
            _wantAmt = _wantBal;
        }

        // If a withdrawal fee is specified, discount the _wantAmt by the withdrawal fee
        if (withdrawFeeFactor < withdrawFeeFactorMax) {
            _wantAmt = (_wantAmt * withdrawFeeFactor) / withdrawFeeFactorMax;
        }

        // Finally, transfer the want amount from this contract, back to the ZorroController contract
        IERC20Upgradeable(wantAddress).safeTransfer(
            zorroControllerAddress,
            _wantAmt
        );

        // Rebalance
        _farm();
    }

    /// @notice Withdraws specified amount of underlying and rebalances
    /// @param _amount Amount of underlying to withdraw
    function _withdrawSome(uint256 _amount) internal {
        // Rebalance first, based on withdrawal amount
        _rebalance(_amount);

        // Calc balance of underlying
        uint256 _balance = ILendingToken(poolAddress).balanceOfUnderlying(
            address(this)
        );

        // Safety: Cap amount to balance in case of rounding errors
        if (_amount > _balance) _amount = _balance;

        // Attempt to redeem underlying token
        require(
            ILendingToken(poolAddress).redeemUnderlying(_amount) == 0,
            "_withdrawSome: redeem failed"
        );
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
        // Approve spending
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            vaultActions,
            _amount
        );

        // Exchange
        return
            VaultActionsLending(vaultActions).exchangeWantTokenForUSD(
                _amount,
                VaultActionsLending.ExchangeWantTokenForUSDParams({
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

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {
        _farm();
    }

    /// @notice Function for farming want token
    function _farm() internal override {
        // Supply the underlying token
        _supplyWant();

        // Leverage up to target leverage (using supply-borrow)
        _rebalance(0);
    }

    /// @notice To be implemented by child contract
    function _unfarm(uint256 _amount) internal virtual override;

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
        ILendingToken(poolAddress).mint(_wantBal);
    }

    /// @notice Maintains target leverage amount, within tolerance
    /// @param _withdrawAmt The amount of tokens to deleverage for withdrawal
    function _rebalance(uint256 _withdrawAmt) internal {
        /* Init */

        // Be initial supply balance of underlying.
        uint256 _ox = ILendingToken(poolAddress).balanceOfUnderlying(
            address(this)
        );
        // If no supply, nothing to do so exit.
        if (_ox == 0) return;

        // If withdrawal greater than balance of underlying, cap it (account for rounding)
        if (_withdrawAmt >= _ox) _withdrawAmt = _ox - 1;

        // Init
        (
            uint256 _x,
            uint256 _y,
            uint256 _c,
            uint256 _L,
            uint256 _currentL,
            uint256 _liquidityAvailable
        ) = VaultActionsLending(vaultActions).levLendingParams(
                _withdrawAmt,
                _ox,
                comptrollerAddress,
                poolAddress,
                targetBorrowLimit
            );

        /* Leverage targeting */

        if (_currentL < _L && (_L - _currentL) > targetBorrowLimitHysteresis) {
            // If BELOW leverage target and below hysteresis envelope

            // Calculate incremental amount to borrow:
            uint256 _dy = VaultActionsLending(vaultActions)
                .calcIncBorrowBelowTarget(
                    _x,
                    _y,
                    _ox,
                    _c,
                    _L,
                    _liquidityAvailable
                );

            // Borrow incremental amount
            ILendingToken(poolAddress).borrow(_dy);

            // Supply the amount borrowed
            _supplyWant();
        } else {
            // If ABOVE leverage target, iteratively deleverage until within hysteresis envelope
            while (
                _currentL > _L &&
                (_currentL - _L) > targetBorrowLimitHysteresis
            ) {
                // Calculate incremental amount to borrow:
                uint256 _dy = VaultActionsBenqiLending(vaultActions)
                    .calcIncBorrowAboveTarget(
                        _x,
                        _y,
                        _ox,
                        _c,
                        _L,
                        _liquidityAvailable
                    );

                // Redeem underlying increment. Return val must be 0 (success)
                require(
                    ILendingToken(poolAddress).redeemUnderlying(_dy) == 0,
                    "rebal fail"
                );

                // Decrement supply bal by amount repaid
                _ox = _ox - _dy;
                // Cap withdrawal amount to new supply (account for rounding)
                if (_withdrawAmt >= _ox) _withdrawAmt = _ox - 1;
                // Adjusted supply decremented by withdrawal amount
                _x = _ox - _withdrawAmt;

                // Cap incremental borrow-repay to total amount borrowed
                if (_dy > _y) _dy = _y;
                // Allow pool to spend underlying
                IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
                    poolAddress,
                    _dy
                );
                // Repay borrowed amount (increment)
                ILendingToken(poolAddress).repayBorrow(_dy);
                // Decrement total amount borrowed
                _y = _y - _dy;

                // Update current leverage (borrowed / supplied)
                _currentL = _y * 1e18 / _x;
                // Update current liquidity of underlying pool
                _liquidityAvailable = ILendingToken(poolAddress).getCash();
            }
        }
    }

    /// @notice Calc want token locked, accounting for leveraged supply/borrow
    /// @return amtLocked The adjusted wantLockedTotal quantity
    function wantTokenLockedAdj() public returns (uint256 amtLocked) {
        return
            VaultActionsLending(vaultActions).wantTokenLockedAdj(
                address(this),
                token0Address,
                poolAddress
            );
    }
}
