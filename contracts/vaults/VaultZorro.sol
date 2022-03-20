// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./_VaultBase.sol";


/// @title VaultZorro. The Vault for staking the Zorro token
/// @dev Only to be deployed on BSC (the home of the ZOR token)
contract VaultZorro is VaultBase {
    /* Libraries */
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeSwapUni for IAMMRouter02;

    /* Constructor */
    /// @notice Constructor
    /// @dev NOTE: Only to be deployed on home chain!
    /// @param _addresses : [gov, Zorro controller, Zorro token, Uni v2 router address]
    /// @param _pid : The pool ID in the Zorro Controller
    /// @param _fees : [_controllerFee, _buyBackRate, _entranceFeeFactor, _withdrawFeeFactor]
    /// @param _token0ToUSDCPath Router path to swap from Zorro to USDC
    /// @param _USDCToToken0Path Router path to swap from USDC to ZORRO
    constructor(
        address[] memory _addresses,
        uint256 _pid,
        uint256[] memory _fees,
        address[] memory _token0ToUSDCPath,
        address[] memory _USDCToToken0Path
    ) {
        // Key addresses
        govAddress = _addresses[0];
        zorroControllerAddress = _addresses[1];
        ZORROAddress = _addresses[2];
        wantAddress = _addresses[2];
        token0Address = _addresses[2];
        rewardsAddress = _addresses[2];
        uniRouterAddress = _addresses[3];

        // Vault characteristics
        pid = _pid;
        isCOREStaking = false;
        isSingleAssetDeposit = true;
        isZorroComp = false;
        isHomeChain = true;

        // Swap paths
        token0ToUSDCPath = _token0ToUSDCPath;
        USDCToToken0Path = _USDCToToken0Path;

        // Fees
        controllerFee = _fees[0];
        buyBackRate = _fees[1];
        entranceFeeFactor = _fees[2];
        withdrawFeeFactor = _fees[3];
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _wantAmt amount of Want token to deposit/stake
    /// @return Number of shares added
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
        IERC20(wantAddress).safeTransferFrom(msg.sender, address(this), _wantAmt);

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
    /// @param _priceData A PriceData struct containing the latest prices for relevant tokens
    /// @return Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSDC,
        uint256 _maxMarketMovementAllowed,
        PriceData calldata _priceData
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        // Get balance of deposited USDC
        uint256 _balUSDC = IERC20(tokenUSDCAddress).balanceOf(address(this));
        // Check that USDC was actually deposited
        require(_amountUSDC > 0, "USDC deposit must be > 0");
        require(_amountUSDC <= _balUSDC, "USDC desired exceeded bal");

        // Swap USDC for token0
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amountUSDC.div(2),
            _priceData.tokenUSDC,
            _priceData.token0,
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
    /// @param _harvestOnly unused for this function (only here to comply with interface)
    /// @return the number of shares removed
    function withdrawWantToken(address _account, bool _harvestOnly)
        public
        override
        onlyZorroController
        onlyOwner
        nonReentrant
        returns (uint256)
    {
        uint256 _userNumShares = userShares[_account];
        uint256 _wantAmt = IERC20(wantAddress).balanceOf(address(this)).mul(_userNumShares).div(sharesTotal);

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
    /// @param _priceData A PriceData struct containing the latest prices for relevant tokens
    /// @return Amount of USDC token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        PriceData calldata _priceData
    ) public virtual override onlyZorroController returns (uint256) {
        // Preflight checks
        require(_amount > 0, "Want amt must be > 0");

        // Safely transfer Want token from sender
        IERC20(wantAddress).safeTransferFrom(msg.sender, address(this), _amount);

        // Swap token0 for USDC
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amount,
            _priceData.token0,
            _priceData.tokenUSDC,
            _maxMarketMovementAllowed,
            token0ToUSDCPath,
            msg.sender,
            block.timestamp.add(600)
        );

        return IERC20(tokenUSDCAddress).balanceOf(address(this));
    }

    /// @notice The main compounding (earn) function. Reinvests profits since the last earn event.
    /// @param _maxMarketMovementAllowed The max slippage allowed. (included here just to implement interface; otherwise unused)
    /// @param _priceData A PriceData struct containing the latest prices for relevant tokens
    function earn(
        uint256 _maxMarketMovementAllowed,
        PriceData calldata _priceData
    )
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
        PriceData calldata _priceData
    ) internal override {
        // Dummy function to implement interface
    }

    function _revShareOnChain(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed,
        PriceData calldata _priceData
    ) internal override {
        // Dummy function to implement interface
    }

    function _swapEarnedToUSDC(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed,
        PriceData calldata _priceData
    ) internal override {
        // Dummy function to implement interface
    }
}
