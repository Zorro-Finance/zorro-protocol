// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/Zorro/Vaults/IVaultZorro.sol";

import "./actions/VaultActionsZorro.sol";

import "./_VaultBase.sol";

/// @title VaultZorro. The Vault for staking the Zorro token
/// @dev Only to be deployed on the home of the ZOR token
contract VaultZorro is IVaultZorro, VaultBase {
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */

    /// @notice Upgradeable constructor
    /// @dev NOTE: Only to be deployed on home chain!
    /// @param _initValue A VaultZorroInit struct that contains all constructor args
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultZorroInit memory _initValue
    ) public initializer {
        // Super call
        VaultBase.initialize(_timelockOwner, _initValue.baseInit);
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _wantAmt amount of Want token to deposit/stake
    /// @return sharesAdded Number of shares added
    function depositWantToken(uint256 _wantAmt)
        public
        override(IVault, VaultBase)
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
        sharesTotal = sharesTotal + sharesAdded;

        // Increment principal debt to account for cash flow
        principalDebt += _wantAmt;
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
        // Preflight checks
        require(_wantAmt > 0, "negWant");

        // Calc current want equity
        uint256 _wantEquity = IVaultActions(vaultActions).currentWantEquity(
            address(this)
        );

        // Shares removed is proportional to the % of total Want tokens locked that _wantAmt represents
        sharesRemoved = (_wantAmt * sharesTotal) / _wantEquity;

        // Safety: cap the shares to the total number of shares
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        // Decrement the total shares by the sharesRemoved
        sharesTotal -= sharesRemoved;

        // If a withdrawal fee is specified, discount the _wantAmt by the withdrawal fee
        if (withdrawFeeFactor < feeDenominator) {
            _wantAmt = (_wantAmt * withdrawFeeFactor) / feeDenominator;
        }

        // Safety: Check balance of this contract's Want tokens held, and cap _wantAmt to that value
        uint256 _wantBal = IERC20Upgradeable(wantAddress).balanceOf(
            address(this)
        );
        if (_wantAmt > _wantBal) {
            _wantAmt = _wantBal;
        }

        // Decrement principal debt to account for cash flow
        principalDebt -= _wantAmt;

        // Finally, transfer the want amount from this contract, back to the ZorroController contract
        IERC20Upgradeable(wantAddress).safeTransfer(
            zorroControllerAddress,
            _wantAmt
        );
    }

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {}

    /// @notice Implement dummy _farm function to satisfy abstract contract 
    function _farm() internal override {}

    /// @notice Implement dummy _unfarm function to satisfy abstract contract 
    function _unfarm(uint256 _amount) internal override {}

    /// @notice The main compounding (earn) function. Reinvests profits since the last earn event.
    function earn()
        public
        override(IVault, VaultBase)
        nonReentrant
        whenNotPaused
    {
        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // (No distribution of fees/buyback)

        // Update last earned block
        lastEarnBlock = block.number;
    }
}
