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
    // TODO: token0address should be the Zorro token address
    constructor(
        address[] memory _addresses,
        uint256 _pid,
        bool _isCOREStaking,
        bool _isSameAssetDeposit,
        bool _isZorroComp,
        address[] memory _earnedToZORROPath,
        address[] memory _earnedToToken0Path,
        address[] memory _earnedToToken1Path,
        address[] memory _token0ToEarnedPath,
        address[] memory _token1ToEarnedPath,
        uint256[] memory _fees // [_controllerFee, _buyBackRate, _entranceFeeFactor, _withdrawFeeFactor]
    ) {
        wbnbAddress = _addresses[0];
        govAddress = _addresses[1];
        zorroControllerAddress = _addresses[2];
        ZORROAddress = _addresses[3];

        wantAddress = _addresses[4];
        token0Address = _addresses[5];
        token1Address = _addresses[6];
        earnedAddress = _addresses[7];

        farmContractAddress = _addresses[8];
        pid = _pid;
        isCOREStaking = _isCOREStaking;
        isSameAssetDeposit = _isSameAssetDeposit;
        isZorroComp = _isZorroComp;

        uniRouterAddress = _addresses[9];
        earnedToZORROPath = _earnedToZORROPath;
        earnedToToken0Path = _earnedToToken0Path;
        earnedToToken1Path = _earnedToToken1Path;
        token0ToEarnedPath = _token0ToEarnedPath;
        token1ToEarnedPath = _token1ToEarnedPath;

        controllerFee = _fees[0];
        rewardsAddress = _addresses[10];
        buyBackRate = _fees[1];
        burnAddress = _addresses[11];
        entranceFeeFactor = _fees[2];
        withdrawFeeFactor = _fees[3];

        transferOwnership(zorroControllerAddress);
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
        // Check to make sure Want token is already on this contract and held for this user
        require(
            _wantAmt <= wantTokensInHolding[_account],
            "Exceeds Want tokens in holding for this user"
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

        // Clear holdings
        wantTokensInHolding[_account] = 0;

        return sharesAdded;
    }

    /// @notice Performs necessary operations to convert USDC into Want token
    /// @param _account The user account to transfer USDC from
    /// @param _amount The USDC quantity to exchange
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return Amount of Want token obtained
    function exchangeUSDForWantToken(
        address _account,
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        // Update temporary holdings for user
        wantTokensInHolding[_account] = _amount;

        return _amount;
    }

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {}

    /// @notice Withdraw Want tokens from the Farm contract
    /// @param _account address of user
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal (Should ALWAYS be true for this contract)
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
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        if (_wantAmt > wantAmt) {
            _wantAmt = wantAmt;
        }
        // Safety: cap _wantAmt at the total quantity of Want tokens locked
        if (wantLockedTotal < _wantAmt) {
            _wantAmt = wantLockedTotal;
        }

        // Decrement the total Want locked tokens by the _wantAmt
        wantLockedTotal = wantLockedTotal.sub(_wantAmt);

        // Finally, transfer the want amount from this contract, back to the ZorroController contract
        IERC20(wantAddress).safeTransfer(zorroControllerAddress, _wantAmt);

        // Update holdings
        wantTokensInHolding[_account] = _wantAmt;

        return sharesRemoved;
    }

    /// @notice Converts Want token back into USD to be ready for withdrawal
    /// @param _account The user account to transfer USDC from
    /// @param _amount The Want token quantity to exchange
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return Amount of USDC token obtained
    function exchangeWantTokenForUSD(
        address _account,
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) public virtual override onlyZorroController returns (uint256) {
        // Require Want tokens to already be in holdings
        require(_amount <= wantTokensInHolding[_account], "Requested more Want tokens than are in holding");

        // Clear out temporary holdings for user
        wantTokensInHolding[_account] = 0;

        return _amount;
    }

    /// @notice The main compounding (earn) function. Reinvests profits since the last earn event.
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    function earn(uint256 _maxMarketMovementAllowed)
        public
        override
        nonReentrant
        whenNotPaused
    {
        // TODO: Take in price oracle to perform safe swaps
        // Only to be run if this contract is configured for auto-comnpounding
        require(isZorroComp, "!isZorroComp");
        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // Get the balance of the Earned token on this contract (USDC)
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        // No distribution of fees/buyback

        // Approve the router contract
        IERC20(earnedAddress).safeApprove(uniRouterAddress, 0);
        // Allow the router contract to spen up to earnedAmt
        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            earnedAmt
        );

        // Swap earned token (USDC) to token0 (ZORRO)
        IAMMRouter02(uniRouterAddress).safeSwap(
            earnedAmt,
            _maxMarketMovementAllowed,
            earnedToToken0Path,
            address(this),
            block.timestamp.add(600)
        );

        // Update last earned block
        lastEarnBlock = block.number;

        // Update want locked total
        wantLockedTotal = IERC20(token0Address).balanceOf(address(this));
    }
}
