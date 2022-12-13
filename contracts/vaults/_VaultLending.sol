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
        // Lending params
        targetBorrowLimit = _initValue.targetBorrowLimit;
        targetBorrowLimitHysteresis = _initValue.targetBorrowLimitHysteresis;

        // Addresses
        comptrollerAddress = _initValue.comptrollerAddress;
        lendingToken = _initValue.lendingToken;

        // Super call
        VaultBase.initialize(_timelockOwner, _initValue.baseInit);
    }

    /* State */

    uint256 public targetBorrowLimit; // Max borrow rate % (1e18 = 100%)
    uint256 public targetBorrowLimitHysteresis; // +/- envelope (1% = 1e16)
    address public comptrollerAddress; // Unitroller address
    address public lendingToken; // Lending contract address (e.g. vToken)
    uint256 public supplyBal; // Aggregate supply balance of underlying token on lending contract, by this vault
    uint256 public borrowBal; // Aggregate borrow balance of underlying token on lending contract, by this vault

    /* Setters */

    function setTargetBorrowLimits(
        uint256 _targetBorrowLimit,
        uint256 _hysteresis
    ) external onlyOwner {
        // Set target borrow limit settings
        targetBorrowLimit = _targetBorrowLimit;
        targetBorrowLimitHysteresis = _hysteresis;

        // Rebalance to reflect new settings
        _rebalance(0);
    }

    function setComptrollerAddress(address _comptroller) external onlyOwner {
        comptrollerAddress = _comptroller;
    }

    function setLendingToken(address _lendingToken) external onlyOwner {
        lendingToken = _lendingToken;
    }

    /// @notice Update balance of supply and borrow
    function updateBalance() public {
        supplyBal = ILendingToken(lendingToken).balanceOfUnderlying(
            address(this)
        ); // a payable function because of acrueInterest()
        borrowBal = ILendingToken(lendingToken).borrowBalanceCurrent(
            address(this)
        );
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _wantAmt amount of underlying token to deposit/stake
    /// @return sharesAdded uint256 Number of shares added
    function depositWantToken(uint256 _wantAmt)
        public
        override(IVault, VaultBase)
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 sharesAdded)
    {
        // Update balance
        updateBalance();

        // Deposit
        return super.depositWantToken(_wantAmt);
    }

    /// @notice Fully withdraw Want tokens from the Farm contract (100% withdrawals only)
    /// @param _wantAmt The amount of Want token to withdraw
    /// @return sharesRemoved The number of shares removed
    function withdrawWantToken(uint256 _wantAmt)
        public
        override(IVault, VaultBase)
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256 sharesRemoved)
    {
        // Update balance
        updateBalance();

        // Withdraw
        return super.withdrawWantToken(_wantAmt);
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
        ) = IVaultActionsLending(vaultActions).levLendingParams(
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
            uint256 _dy = IVaultActionsLending(vaultActions)
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
                _currentL > _L && (_currentL - _L) > targetBorrowLimitHysteresis
            ) {
                // Calculate incremental amount to borrow:
                uint256 _dy = IVaultActionsLending(vaultActions)
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
                _currentL = (_y * 1e18) / _x;
                // Update current liquidity of underlying pool
                _liquidityAvailable = ILendingToken(poolAddress).getCash();
            }
        }
    }
}
