// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./libraries/SafeERC20.sol";

import "./interfaces/IAMMFarm.sol";

import "./interfaces/IAcryptosFarm.sol";

import "./interfaces/IAcryptosVault.sol";

import "./interfaces/IERC20.sol";

import "./libraries/SafeMath.sol";

import "./VaultBase.sol";

import "./interfaces/IBalancerVault.sol";

/// @title Vault contract for Acryptos single token strategies (e.g. for lending)
contract VaultAcryptosSingle is VaultBase {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* Constructor */
    // TODO: @param descriptions
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
        // TODO: Allow up to 4 token addresses
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

    /* State */

    address public balancerVaultAddress =
        0xa82f327BBbF0667356D2935C6532d164b06cEced; // Address of Balancer/ACSI.finance Vault for swaps etc.
    bytes32 public balancerPoolEarnedToTokens =
        0x894ed9026de37afd9cce1e6c0be7d6b510e3ffe5000100000000000000000001; // The Acryptos ACSI.finance pool ID for swapping Earned token to underlying tokens.
    uint256 balancerPoolEarnedWeightBasisPoints = 4000;
    uint256 balancerPoolToken0WeightBasisPoints = 3000;
    // TODO: Put this in constructor
    uint256 numTokens; // Number of tokens in the LP pool (number between 1 and 4, inclusive)

    /* Config */

    function setBalancerVaultAddress(address _balancerVaultAddress)
        public
        onlyOwner
    {
        balancerVaultAddress = _balancerVaultAddress;
    }

    function setBalancerPoolEarnedToTokens(bytes32 _balancerPoolEarnedToToken)
        public
        onlyOwner
    {
        balancerPoolEarnedToTokens = _balancerPoolEarnedToToken;
    }

    function setBalancerPoolEarnedWeightBasisPoints(
        uint256 _balancerPoolEarnedWeightBasisPoints
    ) public onlyOwner {
        balancerPoolEarnedWeightBasisPoints = _balancerPoolEarnedWeightBasisPoints;
    }

    function setBalancerPoolToken0WeightBasisPoints(
        uint256 _balancerPoolToken0WeightBasisPoints
    ) public onlyOwner {
        balancerPoolToken0WeightBasisPoints = _balancerPoolToken0WeightBasisPoints;
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _account address of user that this deposit is intended for
    /// @param _wantAmt amount of Want token to deposit/stake
    /// @return Number of shares added
    function depositWantToken(address _account, uint256 _wantAmt)
        public
        virtual
        override
        onlyOwner
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

        if (isZorroComp) {
            // If this contract is meant for Autocompounding, start to farm the staked token
            _farm();
        } else {
            // Otherwise, simply increment the quantity of total Want tokens locked
            wantLockedTotal = wantLockedTotal.add(_wantAmt);
        }

        // Clear holdings
        wantTokensInHolding[_account];

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
    ) public override returns (uint256) {
        // TODO: For all swaps, join/exit pools: Ensure to use safety features to prevent front running
        // Swap USDC for tokens
        // TODO Consider using a batch swap here
        // Swap Token0
        // --
        if (numTokens > 1) {
            // Swap Token1
        }
        if (numTokens > 2) {
            // Swap Token2
        }
        if (numTokens > 3) {
            // Swap Token3
        }

        // Deposit tokens to get Want token (e.g. LP token)
        // TODO: joinPool: https://dev.balancer.fi/resources/joins-and-exits/pool-joins 

        // Update temporary holdings for user
        wantTokensInHolding[_account] = 0; // TODO <- change this to want tokens obtained.
    }

    /// @notice Public function for farming Want token.
    function farm() public virtual nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
    function _farm() internal virtual {
        // Farming should only occur if this contract is set for autocompounding
        require(isZorroComp, "!isZorroComp");

        // Get the Want token stored on this contract
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        // Increment the total Want tokens locked into this contract
        wantLockedTotal = wantLockedTotal.add(wantAmt);
        // Allow the farm contract (e.g. MasterChef) the ability to transfer up to the Want amount
        IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, wantAmt);

        // Deposit the Want tokens in the Farm contract
        IAcryptosFarm(farmContractAddress).deposit(wantAddress, wantAmt);
    }

    /// @notice Internal function for unfarming Want token. Responsible for unstaking Want token from MasterChef/MasterApe contracts
    /// @param _wantAmt the amount of Want tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _wantAmt) internal virtual {
        // Withdraw the Want tokens from the Farm contract
        IAcryptosFarm(farmContractAddress).withdraw(wantAddress, _wantAmt);
    }

    /// @notice Withdraw Want tokens from the Farm contract
    /// @param _account The address of the owner of vault investment
    /// @param _wantAmt the amount of Want tokens to withdraw
    /// @return the number of shares removed
    function withdrawWantToken(address _account, uint256 _wantAmt)
        public
        virtual
        override
        onlyOwner
        nonReentrant
        returns (uint256)
    {
        // Want amount must be greater than 0
        require(_wantAmt > 0, "_wantAmt <= 0");

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

        // If this contract is designated for auto compounding, unfarm the Want tokens
        if (isZorroComp) {
            _unfarm(_wantAmt);
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
    ) public virtual override returns (uint256) {
        // TODO
    }

    /// @notice The main compounding (earn) function. Reinvests profits since the last earn event.
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    function earn(uint256 _maxMarketMovementAllowed) public virtual override nonReentrant whenNotPaused {
        // Only to be run if this contract is configured for auto-comnpounding
        require(isZorroComp, "!isZorroComp");
        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // Harvest farm tokens
        _unfarm(0);

        // If the earned address is the WBNB token, wrap all BNB owned by this contract
        if (earnedAddress == wbnbAddress) {
            _wrapBNB();
        }

        // Get the balance of the Earned token on this contract (ACS, etc.)
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        // Reassign value of earned amount after distributing fees
        earnedAmt = distributeFees(earnedAmt);
        // Reassign value of earned amount after buying back a certain amount of Zorro
        earnedAmt = buyBack(earnedAmt);

        // If staking a single token (CAKE, BANANA), farm that token and exit
        if (isCOREStaking || isSameAssetDeposit) {
            // Update the last earn block
            lastEarnBlock = block.number;
            _farm();
            return;
        }

        // Approve the Balancer Vault contract for swaps
        IERC20(earnedAddress).safeApprove(balancerVaultAddress, 0);
        // Allow the Balancer Vault contract to spen up to earnedAmt
        IERC20(earnedAddress).safeIncreaseAllowance(
            balancerVaultAddress,
            earnedAmt
        );

        // Swap Earned token to token0 if token0 is not the Earned token
        if (earnedAddress != token0Address) {
            swapAcryptos(
                earnedAmt,
                earnedAddress,
                token0Address,
                slippageFactor
            );
        }

        // Get balance of token0
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        // Provided that token0 quantity is > 0, redeposit
        if (token0Amt > 0) {
            // Increase the allowance of the AcryptosVault to spend token0 (for deposit)
            IERC20(token0Address).safeIncreaseAllowance(wantAddress, token0Amt);
            // Re-deposit the newly swapped token0 to get new Want tokens minted
            IAcryptosVault(wantAddress).deposit(token0Amt);
        }

        // Update last earned block
        lastEarnBlock = block.number;

        // Farm Want tokens obtained
        _farm();
    }

    function swapAcryptos(
        uint256 _amountIn,
        address _assetIn,
        address _assetOut,
        uint256 _slippageFactor
    ) internal {
        // Determine the limit based on the exchange rate
        uint256 limit = getExchangeRate(balancerVaultAddress, _assetOut, _assetIn)
            .mul(_slippageFactor)
            .div(1000);
        // Swap Earned token to token0
        IBalancerVault(balancerVaultAddress).swap(
            SingleSwap({
                poolId: balancerPoolEarnedToTokens,
                kind: SwapKind.GIVEN_IN,
                assetIn: IAsset(_assetIn),
                assetOut: IAsset(_assetOut),
                amount: _amountIn,
                userData: ""
            }),
            FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            }),
            limit,
            block.timestamp.add(600)
        );
    }

    /// @notice Calculates exchange rate of token B per token A. Note: Ignores swap fees!
    /// @param _balancerVaultAddress Address of Acryptos/Balancer Vault
    /// @param _tokenA token A address
    /// @param _tokenB token B address
    /// @return exhange rate of token B per token A
    function getExchangeRate(
        address _balancerVaultAddress,
        address _tokenA, 
        address _tokenB
    ) internal returns (uint256) {
        // Calculate current balances of each token (Earned, and token0)
        (uint256 cashB, , , ) = IBalancerVault(_balancerVaultAddress)
            .getPoolTokenInfo(
                balancerPoolEarnedToTokens,
                IERC20(_tokenB)
            );
        (uint256 cashA, , , ) = IBalancerVault(_balancerVaultAddress)
            .getPoolTokenInfo(
                balancerPoolEarnedToTokens,
                IERC20(_tokenA)
            );
        // Return exchange rate, accounting for weightings
        // TODO - needs to be generalized for all 4 tokens
        return
            (cashA.div(balancerPoolToken0WeightBasisPoints)).div(
                cashB.div(balancerPoolEarnedWeightBasisPoints)
            );
    }
}