// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./_VaultBase.sol";

import "../libraries/PriceFeed.sol";

/// @title VaultZorro. The Vault for staking the Zorro token
/// @dev Only to be deployed on the home of the ZOR token
contract VaultZorro is VaultBase {
    /* Libraries */
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /* Constructor */
    /// @notice Upgradeable constructor
    /// @dev NOTE: Only to be deployed on home chain!
    /// @param _initValue A VaultZorroInit struct that contains all constructor args
    /// @param _timelockOwner The designated timelock controller address to act as owner
    function initialize(
        address _timelockOwner,
        VaultZorroInit memory _initValue
    ) public {
        // Vault config
        pid = _initValue.pid;
        isCOREStaking = false;
        isSingleAssetDeposit = true;
        isZorroComp = false;
        isHomeChain = true;

        // Addresses
        govAddress = _initValue.keyAddresses.govAddress;
        onlyGov = true;
        zorroControllerAddress = _initValue.keyAddresses.zorroControllerAddress;
        ZORROAddress = _initValue.keyAddresses.ZORROAddress;
        wantAddress = _initValue.keyAddresses.wantAddress;
        token0Address = _initValue.keyAddresses.token0Address;
        rewardsAddress = _initValue.keyAddresses.rewardsAddress;
        uniRouterAddress = _initValue.keyAddresses.uniRouterAddress;
        tokenUSDCAddress = _initValue.keyAddresses.tokenUSDCAddress;

        // Fees
        controllerFee = _initValue.fees.controllerFee;
        buyBackRate = _initValue.fees.buyBackRate;
        revShareRate = _initValue.fees.revShareRate;
        entranceFeeFactor = _initValue.fees.entranceFeeFactor;
        withdrawFeeFactor = _initValue.fees.withdrawFeeFactor;

        // Swap paths
        USDCToToken0Path = _initValue.USDCToToken0Path;
        token0ToUSDCPath = _reversePath(USDCToToken0Path);

        // Price feeds
        token0PriceFeed = AggregatorV3Interface(
            _initValue.priceFeeds.token0PriceFeed
        );

        // Super call
        VaultBase.initialize(_timelockOwner);
    }

    /* Structs */

    struct VaultZorroInit {
        uint256 pid;
        VaultAddresses keyAddresses;
        address[] USDCToToken0Path;
        VaultFees fees;
        VaultPriceFeeds priceFeeds;
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _wantAmt amount of Want token to deposit/stake
    /// @return uiint256 Number of shares added
    function depositWantToken(address _account, uint256 _wantAmt)
        public
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

        // Update want locked total
        wantLockedTotal = IERC20(token0Address).balanceOf(address(this));

        return sharesAdded;
    }

    /// @notice Performs necessary operations to convert USDC into Want token
    /// @param _amountUSDC The USDC quantity to exchange
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

        // Increase allowance
        IERC20(tokenUSDCAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _amountUSDC
        );

        // Swap USDC for token0
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amountUSDC.div(2),
            1e12,
            _token0ExchangeRate,
            _maxMarketMovementAllowed,
            USDCToToken0Path,
            address(this),
            block.timestamp.add(600)
        );

        // Calculate resulting want token balance
        uint256 _wantAmt = IERC20(wantAddress).balanceOf(address(this));

        // Transfer back to sender
        IERC20(wantAddress).safeTransfer(zorroControllerAddress, _wantAmt);

        return _wantAmt;
    }

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {}

    /// @notice Withdraw Want tokens from the Farm contract
    /// @param _account address of user
    /// @param _wantAmt The amount of Want token to withdraw
    /// @return uint256 the number of shares removed
    function withdrawWantToken(address _account, uint256 _wantAmt)
        public
        override
        onlyZorroController
        onlyOwner
        nonReentrant
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

        // If a withdrawal fee is specified, discount the _wantAmt by the withdrawal fee
        if (withdrawFeeFactor < withdrawFeeFactorMax) {
            _wantAmt = _wantAmt.mul(withdrawFeeFactor).div(
                withdrawFeeFactorMax
            );
        }

        // Safety: Check balance of this contract's Want tokens held, and cap _wantAmt to that value
        uint256 _wantBal = IERC20(wantAddress).balanceOf(address(this));
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
        IERC20(wantAddress).safeTransfer(zorroControllerAddress, _wantAmt);

        return sharesRemoved;
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal
    /// @param _amount The Want token quantity to exchange
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. (included here just to implement interface; otherwise unused)
    /// @return uint256 Amount of USDC token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) public virtual override onlyZorroController returns (uint256) {
        // Preflight checks
        require(_amount > 0, "Want amt must be > 0");

        // Safely transfer Want token from sender
        IERC20(wantAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Use price feed to determine exchange rates
        uint256 _token0ExchangeRate = token0PriceFeed.getExchangeRate();

        // Increase allowance
        IERC20(token0Address).safeIncreaseAllowance(uniRouterAddress, _amount);

        // Swap token0 for USDC
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amount,
            _token0ExchangeRate,
            1e12,
            _maxMarketMovementAllowed,
            token0ToUSDCPath,
            msg.sender,
            block.timestamp.add(600)
        );

        return IERC20(tokenUSDCAddress).balanceOf(address(this));
    }

    /// @notice The main compounding (earn) function. Reinvests profits since the last earn event.
    /// @param _maxMarketMovementAllowed The max slippage allowed. (included here just to implement interface; otherwise unused)
    function earn(uint256 _maxMarketMovementAllowed)
        public
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

        // (No distribution of fees/buyback)

        // Update last earned block
        lastEarnBlock = block.number;

        // Update want locked total
        wantLockedTotal = IERC20(token0Address).balanceOf(address(this));
    }

    function _buybackOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal override {
        // Dummy function to implement interface
    }

    function _revShareOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal override {
        // Dummy function to implement interface
    }

    function _swapEarnedToUSDC(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed,
        ExchangeRates memory _rates
    ) internal override {
        // Dummy function to implement interface
    }
}
