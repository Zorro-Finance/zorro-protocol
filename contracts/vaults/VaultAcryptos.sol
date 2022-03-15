// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IAMMFarm.sol";

import "../interfaces/IAcryptosFarm.sol";

import "../interfaces/IAcryptosVault.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./_VaultBase.sol";

import "../interfaces/IBalancerVault.sol";

/// @title Vault contract for Acryptos single token strategies (e.g. for lending)
contract VaultAcryptosSingle is VaultBase {
    /* Libraries */
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeSwapBalancer for IBalancerVault;
    using SafeSwapUni for IAMMRouter02;

    /* Constructor */
    /// @notice Constructor
    /// @param _addresses Array of [govAddress, zorroControllerAddress, ZORROAddress, wantAddress, token0Address, earnedAddress, farmContractAddress, rewardsAddress, poolAddress, uniRouterAddress, zorroLPPool, zorroLPPoolToken0, zorroLPPoolToken1]
    /// @param _pid Pool ID this Vault is associated with
    /// @param _isCOREStaking If true, is for staking just core token of AMM (e.g. CAKE for Pancakeswap, BANANA for Apeswap, etc.). Set to false for Zorro single staking vault
    /// @param _isZorroComp This vault is for compounding. If true, will trigger farming/unfarming on earn events. Set to false for Zorro single staking vault
    /// @param _isHomeChain Whether this contract is deployed on the home chain (BSC)
    /// @param _swapPaths A flattened array of swap paths for a Uniswap style router. Ordered as: [earnedToZORROPath, earnedToToken0Path, earnedToToken1Path, USDCToToken0Path, USDCToToken1Path, earnedToZORLPPoolToken0Path, earnedToZORLPPoolToken1Path, earnedToUSDCPath]
    /// @param _swapPathStartIndexes An array of start indexes within _swapPaths to represent the start of a new swap path
    /// @param _fees Array of [_controllerFee, _buyBackRate, _entranceFeeFactor, _withdrawFeeFactor]
    /// @param _balancerPools Addresses of Balancer pools for performing swaps. Array of [balancerPoolUSDCToWant, balancerPoolUSDCToToken0]
    /// @param _balancerPoolWeights Weights of assets in Balancer pools. Array of [balancerPoolUSDCWeightBasisPoints, balancerPoolWantWeightBasisPoints, balancerPoolEarnWeightBasisPoints, balancerPoolToken0WeightBasisPoints]
    constructor(
        address[] memory _addresses,
        uint256 _pid,
        bool _isCOREStaking,
        bool _isZorroComp,
        bool _isHomeChain,
        address[] memory _swapPaths,
        uint16[] memory _swapPathStartIndexes,
        uint256[] memory _fees,
        bytes32[] memory _balancerPools,
        uint256[] memory _balancerPoolWeights
    ) {
        // Addresses
        govAddress = _addresses[0];
        zorroControllerAddress = _addresses[1];
        ZORROAddress = _addresses[2];
        wantAddress = _addresses[3];
        token0Address = _addresses[4];
        earnedAddress = _addresses[5];
        farmContractAddress = _addresses[6];
        rewardsAddress = _addresses[7];
        poolAddress = _addresses[8];
        uniRouterAddress = _addresses[9];
        zorroLPPool = _addresses[10];
        zorroLPPoolToken0 = _addresses[11];
        zorroLPPoolToken1 = _addresses[12];


        // Vault config
        pid = _pid;
        isCOREStaking = _isCOREStaking;
        isSingleAssetDeposit = true;
        isZorroComp = _isZorroComp;
        isHomeChain = _isHomeChain;

        // Swap paths
        _unpackSwapPaths(_swapPaths, _swapPathStartIndexes);

        // Corresponding reverse paths
        token0ToEarnedPath = _reversePath(earnedToToken0Path);
        token0ToUSDCPath = _reversePath(USDCToToken0Path);

        // Fees
        controllerFee = _fees[0];
        buyBackRate = _fees[1];
        entranceFeeFactor = _fees[2];
        withdrawFeeFactor = _fees[3];

        // Balancer pools
        balancerPoolUSDCToWant = _balancerPools[0];
        balancerPoolUSDCToToken0 = _balancerPools[1];

        // Balancer token weights
        balancerPoolUSDCWeightBasisPoints = _balancerPoolWeights[0];
        balancerPoolWantWeightBasisPoints = _balancerPoolWeights[1];
        balancerPoolEarnWeightBasisPoints = _balancerPoolWeights[2];
        balancerPoolToken0WeightBasisPoints = _balancerPoolWeights[3];
    }

    /* State */

    address public balancerVaultAddress =
        0xa82f327BBbF0667356D2935C6532d164b06cEced; // Address of Balancer/ACSI.finance Vault for swaps etc.
    bytes32 public balancerPoolEarnedToTokens =
        0x894ed9026de37afd9cce1e6c0be7d6b510e3ffe5000100000000000000000001; // The Acryptos ACSI.finance pool ID for swapping Earned token to underlying tokens.
    bytes32 public balancerLPPool;
    address public tokenACS = 0x4197C6EF3879a08cD51e5560da5064B773aa1d29;
    address public tokenACSI = 0x5b17b4d5e4009B5C43e3e3d63A5229F794cBA389;
    bytes32 public balancerPoolUSDCToWant;
    bytes32 public balancerPoolUSDCToToken0;
    uint256 public balancerPoolUSDCWeightBasisPoints;
    uint256 public balancerPoolWantWeightBasisPoints;
    uint256 public balancerPoolEarnWeightBasisPoints;
    uint256 public balancerPoolToken0WeightBasisPoints;

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

    function setBalancerLPPool(bytes32 _balancerLPPool) public onlyOwner {
        balancerLPPool = _balancerLPPool;
    }

    function setTokenACS(address _tokenACS) public onlyOwner {
        tokenACS = _tokenACS;
    }

    function setTokenACSI(address _tokenACSI) public onlyOwner {
        tokenACSI = _tokenACSI;
    }

    function setBalancerPoolUSDCToWant(bytes32 _balancerPoolUSDCToWant)
        public
        onlyOwner
    {
        balancerPoolUSDCToWant = _balancerPoolUSDCToWant;
    }

    function setBalancerPoolUSDCToToken0(bytes32 _balancerPoolUSDCToToken0)
        public
        onlyOwner
    {
        balancerPoolUSDCToToken0 = _balancerPoolUSDCToToken0;
    }

    function setBalancerPoolUSDCWeightBasisPoints(
        uint256 _balancerPoolUSDCWeightBasisPoints
    ) public onlyOwner {
        balancerPoolUSDCWeightBasisPoints = _balancerPoolUSDCWeightBasisPoints;
    }

    function setBalancerPoolWantWeightBasisPoints(
        uint256 _balancerPoolWantWeightBasisPoints
    ) public onlyOwner {
        balancerPoolWantWeightBasisPoints = _balancerPoolWantWeightBasisPoints;
    }

    function setBalancerPoolEarnWeightBasisPoints(
        uint256 _balancerPoolEarnWeightBasisPoints
    ) public onlyOwner {
        balancerPoolEarnWeightBasisPoints = _balancerPoolEarnWeightBasisPoints;
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
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        // Get balance of want token (the deposited amount)
        uint256 _wantBal = IERC20(wantAddress).balanceOf(address(this));
        // Check to see if Want token was actually deposited, Want amount already present
        require(_wantAmt > 0, "Want token deposit must be > 0");
        require(_wantAmt <= _wantBal, "Exceeds Want bal for deposit");

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

        if (isZorroComp) {
            // If this contract is meant for Autocompounding, start to farm the staked token
            _farm();
        } else {
            // Otherwise, simply increment the quantity of total Want tokens locked
            wantLockedTotal = wantLockedTotal.add(_wantAmt);
        }

        return sharesAdded;
    }

    /// @notice Performs necessary operations to convert USDC into Want token
    /// @param _amountUSDC The USDC quantity to exchange (must already be deposited)
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return Amount of Want token obtained
    function exchangeUSDForWantToken(
        uint256 _amountUSDC,
        uint256 _maxMarketMovementAllowed
    ) public override onlyZorroController whenNotPaused returns (uint256) {
        // TODO: Take in current market prices (oracle)

        // Get balance of deposited USDC
        uint256 _balUSDC = IERC20(tokenUSDCAddress).balanceOf(address(this));
        // Check that USDC was actually deposited
        require(_amountUSDC > 0, "USDC deposit must be > 0");
        require(_amountUSDC <= _balUSDC, "USDC desired exceeded bal");

        // Swap USDC for tokens

        // Single asset. Swap from USDC directly to Token0
        _safeSwap(
            tokenUSDCAddress,
            token0Address,
            _amountUSDC,
            _maxMarketMovementAllowed,
            USDCToToken0Path,
            balancerPoolUSDCWeightBasisPoints,
            balancerPoolToken0WeightBasisPoints
        );

        // Get new Token0 balance
        uint256 _token0Bal = IERC20(token0Address).balanceOf(address(this));

        // Deposit token to get Want token
        IAcryptosVault(poolAddress).deposit(_token0Bal);

        // Calculate resulting want token balance
        uint256 _wantAmt = IERC20(wantAddress).balanceOf(address(this));

        // Transfer back to sender
        IERC20(wantAddress).safeTransfer(zorroControllerAddress, _wantAmt);

        return _wantAmt;
    }

    /// @notice Safely swaps tokens using the most suitable protocol based on token
    /// @param _tokenIn Address of the token being swapped
    /// @param _tokenOut Address of the desired token
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    /// @param _balancerPoolTokenInWeightBasisPoints Percentage weight in basis points for _tokenIn (Only required for Balancer-style swaps)
    /// @param _balancerPoolTokenOutWeightBasisPoints Percentage weight in basis points for _tokenOut (Only required for Balancer-style swaps)
    /// @param _path Array of addresses describing the swap path (only required for Uniswap-style swaps. Leave blank for Balancer-style swaps)
    function _safeSwap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _maxMarketMovementAllowed,
        address[] memory _path,
        uint256 _balancerPoolTokenInWeightBasisPoints,
        uint256 _balancerPoolTokenOutWeightBasisPoints
    ) internal {
        if (_tokenIn == tokenACS || _tokenIn == tokenACSI) {
            // If it's for the Acryptos tokens, swap on ACS Finance (Balancer clone) (Better liquidity for these tokens only)
            IBalancerVault(balancerVaultAddress).safeSwap(
                balancerPoolUSDCToWant,
                _amountIn,
                _tokenIn,
                _tokenOut,
                _maxMarketMovementAllowed,
                _balancerPoolTokenInWeightBasisPoints,
                _balancerPoolTokenOutWeightBasisPoints
            );
        } else {
            // Otherwise, swap on normal Pancakeswap (or Uniswap clone) for simplicity & liquidity
            IAMMRouter02(uniRouterAddress).safeSwap(
                _amountIn,
                _maxMarketMovementAllowed,
                _path,
                address(this),
                block.timestamp.add(600)
            );
        }
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

    /// @notice Fully withdraw Want tokens from the Farm contract (100% withdrawals only)
    /// @param _account The address of the owner of vault investment
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @return The number of shares removed
    function withdrawWantToken(address _account, bool _harvestOnly)
        public
        virtual
        override
        onlyZorroController
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        uint256 _wantAmt = 0;
        if (!_harvestOnly) {
            uint256 _userNumShares = userShares[_account];
            _wantAmt = IERC20(wantAddress)
                .balanceOf(address(this))
                .mul(_userNumShares)
                .div(sharesTotal);
        }

        // Shares removed is proportional to the % of total Want tokens locked that _wantAmt represents
        uint256 sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal);
        // Safety: cap the shares to the total number of shares
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        // Decrement the total shares by the sharesRemoved
        sharesTotal = sharesTotal.sub(sharesRemoved);
        userShares[_account] = userShares[_account].sub(sharesRemoved);

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
    /// @param _amount The Want token quantity to exchange
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return Amount of USDC token obtained
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
        // Init
        uint256 _amountUSDC;

        // Calculate Want token balance
        uint256 _wantBal = IERC20(wantAddress).balanceOf(address(this));

        // Preflight checks
        require(_amount <= _wantBal, "Exceeds want bal");

        // Immediately swap the Want token for USDC
        _safeSwap(
            wantAddress,
            tokenUSDCAddress,
            _amount,
            _maxMarketMovementAllowed,
            WantToUSDCPath,
            balancerPoolWantWeightBasisPoints,
            balancerPoolUSDCWeightBasisPoints
        );

        // Calculate USDC balance
        _amountUSDC = IERC20(tokenUSDCAddress).balanceOf(address(this));

        // Transfer back to sender
        IERC20(tokenUSDCAddress).safeTransfer(msg.sender, _amountUSDC);

        return _amountUSDC;
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
        // Only to be run if this contract is configured for auto-comnpounding
        require(isZorroComp, "!isZorroComp");
        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // Harvest farm tokens
        _unfarm(0);

        // Get the balance of the Earned token on this contract (ACS, etc.)
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        // Reassign value of earned amount after distributing fees
        earnedAmt = _distributeFees(earnedAmt);
        // Reassign value of earned amount after buying back a certain amount of Zorro, sharing revenue
        earnedAmt = _buyBackAndRevShare(earnedAmt, _maxMarketMovementAllowed);

        // Swap Earn token for single asset token
        _safeSwap(
            earnedAddress,
            token0Address,
            earnedAmt,
            _maxMarketMovementAllowed,
            earnedToToken0Path,
            balancerPoolEarnWeightBasisPoints,
            balancerPoolToken0WeightBasisPoints
        );

        // Redeposit single asset token to get Want token
        // Get new Token0 balance
        uint256 _token0Bal = IERC20(token0Address).balanceOf(address(this));
        // Deposit token to get Want token
        IAcryptosVault(poolAddress).deposit(_token0Bal);

        // This vault is only for single asset deposits, so farm that token and exit
        // Update the last earn block
        lastEarnBlock = block.number;
        _farm();
    }

    /// @notice Buys back the earned token on-chain, swaps it to add liquidity to the ZOR pool, then burns the associated LP token
    /// @dev Requires funds to be sent to this address before calling. Can be called internally OR by controller
    /// @param _amount The amount of Earn token to buy back  
    function _buybackOnChain(uint256 _amount, uint256 _maxMarketMovementAllowed) internal override {
        // TODO***: Adjust this for Acryptos/balancer protocol
        
        // Authorize spending beforehand
        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _amount
        );

        // Swap to Token 0
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amount.div(2),
            slippageFactor,
            earnedToZORLPPoolToken0Path,
            address(this),
            block.timestamp.add(600)
        );

        // Swap to Token 1
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amount.div(2),
            slippageFactor,
            earnedToZORLPPoolToken1Path,
            address(this),
            block.timestamp.add(600)
        );

        // Enter LP pool
        uint256 token0Amt = IERC20(zorroLPPoolToken0).balanceOf(address(this));
        uint256 token1Amt = IERC20(zorroLPPoolToken1).balanceOf(address(this));
        IERC20(token0Address).safeIncreaseAllowance(
            uniRouterAddress,
            token0Amt
        );
        IERC20(token1Address).safeIncreaseAllowance(
            uniRouterAddress,
            token1Amt
        );
        IAMMRouter02(uniRouterAddress)
            .addLiquidity(
                zorroLPPoolToken0,
                zorroLPPoolToken1,
                token0Amt,
                token1Amt,
                token0Amt.mul(slippageFactor).div(1000),
                token1Amt.mul(slippageFactor).div(1000),
                burnAddress,
                block.timestamp.add(600)
            );
    }

    /// @notice Sends the specified earnings amount as revenue share to ZOR stakers
    /// @param _amount The amount of Earn token to share as revenue with ZOR stakers
    function _revShareOnChain(uint256 _amount, uint256 _maxMarketMovementAllowed) internal override {
        // Authorize spending beforehand
        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            _amount
        );

        // Swap to ZOR
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amount,
            _maxMarketMovementAllowed,
            earnedToZORROPath,
            zorroStakingVault,
            block.timestamp.add(600)
        );
    }

    /// @notice Swaps Earn token to USDC and sends to destination specified
    /// @param _earnedAmount Quantity of Earned tokens
    /// @param _destination Address to send swapped USDC to
    /// @param _maxMarketMovementAllowed Slippage factor. 950 = 5%, 990 = 1%, etc.
    function _swapEarnedToUSDC(
        uint256 _earnedAmount,
        address _destination,
        uint256 _maxMarketMovementAllowed
    ) internal override {
        // TODO: Change to make Acryptos/Balancer compatible
        // Perform swap with Uni router
        IAMMRouter02(uniRouterAddress).safeSwap(
            _earnedAmount,
            _maxMarketMovementAllowed,
            earnedToUSDCPath,
            _destination,
            block.timestamp.add(600)
        );
    }
}
