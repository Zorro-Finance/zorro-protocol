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
    /// @return uint256 Number of shares added
    function depositWantToken(uint256 _wantAmt)
        public
        override(IVault, VaultBase)
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
            sharesAdded =
                (_wantAmt * sharesTotal * entranceFeeFactor) /
                (wantLockedTotal * feeDenominator);
        }
        // Increment the shares
        sharesTotal = sharesTotal + sharesAdded;

        // Update want locked total
        wantLockedTotal = IERC20Upgradeable(token0Address).balanceOf(
            address(this)
        );

        return sharesAdded;
    }

    /// @notice Performs necessary operations to convert USD into Want token
    /// @param _amountUSD The USD quantity to exchange
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
            VaultActionsZorro(vaultActions).exchangeUSDForWantToken(
                _amountUSD,
                VaultActionsZorro.ExchangeUSDForWantParams({
                    stablecoin: defaultStablecoin,
                    tokenZorroAddress: token0Address,
                    zorroPriceFeed: priceFeeds[token0Address],
                    stablecoinPriceFeed: priceFeeds[defaultStablecoin],
                    stablecoinToZorroPath: swapPaths[defaultStablecoin][ZORROAddress]
                }),
                _maxMarketMovementAllowed
            );
    }

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {}

    /// @notice Implement dummy _farm function to satisfy abstract contract 
    function _farm() internal override {}

    /// @notice Implement dummy _unfarm function to satisfy abstract contract 
    function _unfarm(uint256 _amount) internal override {}

    /// @notice Converts Want token back into USD to be ready for withdrawal
    /// @param _amount The Want token quantity to exchange
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. (included here just to implement interface; otherwise unused)
    /// @return uint256 Amount of  token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) public virtual override onlyZorroController returns (uint256) {
        // Allow spending
        IERC20Upgradeable(wantAddress).safeIncreaseAllowance(
            vaultActions,
            _amount
        );

        // Exchange
        return
            VaultActionsZorro(vaultActions).exchangeWantTokenForUSD(
                _amount,
                VaultActionsZorro.ExchangeWantTokenForUSDParams({
                    tokenZorroAddress: token0Address,
                    stablecoin: defaultStablecoin,
                    zorroPriceFeed: priceFeeds[ZORROAddress],
                    stablecoinPriceFeed: priceFeeds[defaultStablecoin],
                    zorroToStablecoinPath: swapPaths[ZORROAddress][defaultStablecoin]
                }),
                _maxMarketMovementAllowed
            );
    }

    /// @notice The main compounding (earn) function. Reinvests profits since the last earn event.
    /// @param _maxMarketMovementAllowed The max slippage allowed. (included here just to implement interface; otherwise unused)
    function earn(uint256 _maxMarketMovementAllowed)
        public
        override(IVault, VaultBase)
        nonReentrant
        whenNotPaused
    {
        // Reqs
        require(_maxMarketMovementAllowed >= 0); // Satisfy compiler warnings of unused var

        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // (No distribution of fees/buyback)

        // Update last earned block
        lastEarnBlock = block.number;

        // Update want locked total
        wantLockedTotal = IERC20Upgradeable(token0Address).balanceOf(
            address(this)
        );
    }
}
