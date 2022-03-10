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

/*
TODO:
*****************
- Convert this contract to ONLY be for singleAssetDeposit
- token0 IS the WANt token
- No joining/exiting pools. Only Swapping
- No need for token0,1,2,3 and no need for all the complex weight-basis-points vars
*****************
*/


/// @title Vault contract for Acryptos single token strategies (e.g. for lending)
contract VaultAcryptosSingle is VaultBase {
    /* Libraries */
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeSwapBalancer for IBalancerVault;
    using SafeSwapUni for IAMMRouter02;

    /* Constructor */
    // TODO: @param descriptions
    constructor(
        address[] memory _addresses,
        uint256 _pid,
        bool _isCOREStaking,
        bool _isSingleAssetDeposit,
        bool _isZorroComp,
        address[] memory _earnedToZORROPath,
        address[] memory _earnedToToken0Path,
        address[] memory _earnedToToken1Path,
        address[] memory _token0ToEarnedPath,
        address[] memory _token1ToEarnedPath,
        uint256[] memory _fees // [_controllerFee, _buyBackRate, _entranceFeeFactor, _withdrawFeeFactor]
    ) {
        govAddress = _addresses[0];
        zorroControllerAddress = _addresses[1];
        ZORROAddress = _addresses[2];

        wantAddress = _addresses[3];
        token0Address = _addresses[4];
        token1Address = _addresses[5];
        // TODO: Allow up to 4 token addresses
        earnedAddress = _addresses[6];

        farmContractAddress = _addresses[7];
        pid = _pid;
        isCOREStaking = _isCOREStaking;
        isSingleAssetDeposit = _isSingleAssetDeposit;
        isZorroComp = _isZorroComp;

        uniRouterAddress = _addresses[8];
        earnedToZORROPath = _earnedToZORROPath;
        earnedToToken0Path = _earnedToToken0Path;
        earnedToToken1Path = _earnedToToken1Path;
        token0ToEarnedPath = _token0ToEarnedPath;
        token1ToEarnedPath = _token1ToEarnedPath;

        controllerFee = _fees[0];
        rewardsAddress = _addresses[9];
        buyBackRate = _fees[1];
        burnAddress = _addresses[10];
        entranceFeeFactor = _fees[2];
        withdrawFeeFactor = _fees[3];

        transferOwnership(msg.sender);
    }

    /* State */

    address public balancerVaultAddress =
        0xa82f327BBbF0667356D2935C6532d164b06cEced; // Address of Balancer/ACSI.finance Vault for swaps etc.
    bytes32 public balancerPoolEarnedToTokens =
        0x894ed9026de37afd9cce1e6c0be7d6b510e3ffe5000100000000000000000001; // The Acryptos ACSI.finance pool ID for swapping Earned token to underlying tokens.
    bytes32 public balancerLPPool; // TODO: Constructor, setter
    address public tokenACS = 0x4197C6EF3879a08cD51e5560da5064B773aa1d29;
    address public tokenACSI = 0x5b17b4d5e4009B5C43e3e3d63A5229F794cBA389;
    bytes32 public balancerPoolUSDCToWant; // TODO: Constructor, setter
    bytes32 public balancerPoolUSDCToToken0; // TODO: Constructor, setter
    bytes32 public balancerPoolUSDCToToken1; // TODO: Constructor, setter
    bytes32 public balancerPoolUSDCToToken2; // TODO: Constructor, setter
    bytes32 public balancerPoolUSDCToToken3; // TODO: Constructor, setter
    // TODO: Put this in constructor, setters (all of this)
    uint256 public balancerPoolUSDCWeightBasisPoints;
    uint256 public balancerPoolWantWeightBasisPoints;
    uint256 public balancerPoolEarnWeightBasisPoints;
    uint256 public balancerPoolToken0WeightBasisPoints;
    uint256 public balancerPoolToken1WeightBasisPoints;
    uint256 public balancerPoolToken2WeightBasisPoints;
    uint256 public balancerPoolToken3WeightBasisPoints;
    uint256 public numTokens; // Number of tokens in the LP pool (number between 1 and 4, inclusive)
    IAsset[] public poolAssets; // Assets for swapping using Balancer protocol. Should follow the order of Token0, Token1, Token2, Token3 up to the number of tokens

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

    function setBalancerPoolWantWeightBasisPoints(
        uint256 _balancerPoolWantWeightBasisPoints
    ) public onlyOwner {
        balancerPoolWantWeightBasisPoints = _balancerPoolWantWeightBasisPoints;
    }

    function setBalancerPoolUSDCWeightBasisPoints(
        uint256 _balancerPoolUSDCWeightBasisPoints
    ) public onlyOwner {
        balancerPoolUSDCWeightBasisPoints = _balancerPoolUSDCWeightBasisPoints;
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
        // Initialize token amounts
        uint256[] memory maxAmountsIn;
        // First check if this is a single asset staking vault or an LP pool
        if (isSingleAssetDeposit) {
            // Single asset. Swap from USDC directly to Want token
            _safeSwap(
                tokenUSDCAddress, 
                wantAddress, 
                _amountUSDC, 
                _maxMarketMovementAllowed, 
                USDCToWantPath,
                balancerPoolUSDCWeightBasisPoints,
                balancerPoolWantWeightBasisPoints
            );
        } else {
            // Swap Token0
            _safeSwap(
                tokenUSDCAddress, 
                token0Address, 
                _amountUSDC.div(numTokens), 
                _maxMarketMovementAllowed, 
                USDCToToken0Path,
                0,
                0
            );
            maxAmountsIn[0] = _amountUSDC.div(numTokens);

            if (numTokens > 1) {
                // Swap Token1
                _safeSwap(
                    tokenUSDCAddress, 
                    token1Address, 
                    _amountUSDC.div(numTokens), 
                    _maxMarketMovementAllowed, 
                    USDCToToken1Path,
                    0,
                    0
                );
                maxAmountsIn[1] = _amountUSDC.div(numTokens);
            }
            if (numTokens > 2) {
                // Swap Token2
                _safeSwap(
                    tokenUSDCAddress, 
                    token2Address, 
                    _amountUSDC.div(numTokens), 
                    _maxMarketMovementAllowed, 
                    USDCToToken2Path,
                    0,
                    0
                );
                maxAmountsIn[2] = _amountUSDC.div(numTokens);
            }
            if (numTokens > 3) {
                // Swap Token3
                _safeSwap(
                    tokenUSDCAddress, 
                    token3Address, 
                    _amountUSDC.div(numTokens), 
                    _maxMarketMovementAllowed, 
                    USDCToToken3Path,
                    0,
                    0
                );
                maxAmountsIn[3] = _amountUSDC.div(numTokens);
            }

            // Deposit tokens to get Want token (e.g. LP token)
            JoinPoolRequest memory req = JoinPoolRequest({
                assets: poolAssets,
                maxAmountsIn: maxAmountsIn,
                userData: "",
                fromInternalBalance: false
            });
            IBalancerVault(balancerVaultAddress).joinPool(
                balancerLPPool,
                address(this),
                address(this),
                req
            );
        }

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
            _wantAmt = IERC20(wantAddress).balanceOf(address(this)).mul(_userNumShares).div(sharesTotal);
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
    ) public virtual override onlyZorroController whenNotPaused returns (uint256) {
        // Init
        uint256 _amountUSDC;

        // Calculate Want token balance
        uint256 _wantBal = IERC20(wantAddress).balanceOf(address(this));
        
        // Preflight checks
        require(_amount <= _wantBal, "Exceeds want bal");

        // Check if vault is for single asset staking
        if (isSingleAssetDeposit) {
            // If so, immediately swap the Want token for USDC

            _safeSwap(
                wantAddress, 
                tokenUSDCAddress,
                _amount, 
                _maxMarketMovementAllowed, 
                WantToUSDCPath, 
                balancerPoolWantWeightBasisPoints, 
                balancerPoolUSDCWeightBasisPoints
            );

            _amountUSDC = IERC20(tokenUSDCAddress).balanceOf(address(this));

        } else {
            // If not, exit the LP pool and swap assets to USDC

            // Exit LP pool
            uint256[] memory minAssetsOut; // TODO: How to calculate the value of LP token?


            ExitPoolRequest memory req = ExitPoolRequest({
                assets: poolAssets,
                minAmountsOut: minAssetsOut,
                userData: "",
                toInternalBalance: false
            });
            IBalancerVault(balancerVaultAddress).exitPool(
                balancerLPPool,
                address(this),
                payable(address(this)),
                req
            );


            uint256 balance0 = IERC20(token0Address).balanceOf(uniPoolAddress);
            uint256 balance1 = IERC20(token1Address).balanceOf(uniPoolAddress);
            uint256 totalSupply = IERC20(uniPoolAddress).totalSupply();
            uint256 amount0Min = (_amount.mul(balance0).div(totalSupply)).mul(_maxMarketMovementAllowed).div(1000);
            uint256 amount1Min = (_amount.mul(balance1).div(totalSupply)).mul(_maxMarketMovementAllowed).div(1000);
            IAMMRouter02(uniRouterAddress).removeLiquidity(
                token0Address, 
                token1Address,  
                _amount,  
                amount0Min,  
                amount1Min,  
                address(this),  
                block.timestamp.add(600)
            );

            // Swap tokens back to USDC
            uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
            uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
            // Swap token0 for USDC
            address[] memory token0ToUSDCPath;
            token0ToUSDCPath[0] = token0Address;
            token0ToUSDCPath[1] = tokenUSDCAddress;
            IAMMRouter02(uniRouterAddress).safeSwap(
                token0Amt,
                _maxMarketMovementAllowed,
                token0ToUSDCPath,
                address(this),
                block.timestamp.add(600)
            );

            // Swap token1 for USDC (if applicable)
            if (token1Address != address(0)) {
                address[] memory token1ToUSDCPath;
                token1ToUSDCPath[0] = token1Address;
                token1ToUSDCPath[1] = tokenUSDCAddress;
                IAMMRouter02(uniRouterAddress).safeSwap(
                    token1Amt,
                    _maxMarketMovementAllowed,
                    token1ToUSDCPath,
                    address(this),
                    block.timestamp.add(600)
                );
            }

            // Calculate USDC balance
            _amountUSDC = IERC20(tokenUSDCAddress).balanceOf(address(this));

        }

        // Transfer back to sender
        IERC20(tokenUSDCAddress).safeTransfer(msg.sender, _amountUSDC);

        return _amountUSDC;
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

        // Get the balance of the Earned token on this contract (ACS, etc.)
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        // Reassign value of earned amount after distributing fees
        earnedAmt = _distributeFees(earnedAmt);
        // Reassign value of earned amount after buying back a certain amount of Zorro, sharing revenue
        earnedAmt = _buyBackAndRevShare(earnedAmt);

        // If staking a single token (CAKE, BANANA), farm that token and exit
        if (isCOREStaking || isSingleAssetDeposit) {
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
            _safeSwap(
                earnedAddress, 
                token0Address, 
                earnedAmt, 
                _maxMarketMovementAllowed, 
                earnedToToken0Path,
                balancerPoolEarnWeightBasisPoints, 
                balancerPoolToken0WeightBasisPoints 
            );
        }

        if (numTokens > 1 && earnedAddress != token1Address) {
            _safeSwap(
                earnedAddress, 
                token1Address, 
                earnedAmt, 
                _maxMarketMovementAllowed, 
                earnedToToken1Path,
                balancerPoolEarnWeightBasisPoints, 
                balancerPoolToken1WeightBasisPoints
            );
        }

        if (numTokens > 2 && earnedAddress != token2Address) {
            _safeSwap(
                earnedAddress, 
                token2Address, 
                earnedAmt, 
                _maxMarketMovementAllowed, 
                earnedToToken2Path,
                balancerPoolEarnWeightBasisPoints, 
                balancerPoolToken2WeightBasisPoints 
            );
        }

        if (numTokens > 3 && earnedAddress != token3Address) {
            _safeSwap(
                earnedAddress, 
                token3Address, 
                earnedAmt, 
                _maxMarketMovementAllowed, 
                earnedToToken3Path,
                balancerPoolEarnWeightBasisPoints, 
                balancerPoolToken3WeightBasisPoints 
            );
        }

        // Get balance of token0
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        uint256 token1Amt = IERC20(token0Address).balanceOf(address(this));
        uint256 token2Amt = IERC20(token0Address).balanceOf(address(this));
        uint256 token3Amt = IERC20(token0Address).balanceOf(address(this));

        // Check balances to determine whether to proceed
        bool shouldRedeposit = false;
        uint256[] memory maxAmountsIn;

        shouldRedeposit = token0Amt > 0;
        maxAmountsIn[0] = token0Amt;
        if (numTokens > 1) {
            shouldRedeposit = shouldRedeposit && token1Amt > 0;
            maxAmountsIn[1] = token1Amt;
        } 
        if (numTokens > 2) {
            shouldRedeposit = shouldRedeposit && token2Amt > 0;
            maxAmountsIn[2] = token2Amt;
        } 
        if (numTokens > 3) {
            shouldRedeposit = shouldRedeposit && token3Amt > 0;
            maxAmountsIn[3] = token3Amt;
        } else {
            revert("Incorrect numTokens");
        }
        if (shouldRedeposit) {
            // If eligible for redeposit, get Want token by providing liquidity
            JoinPoolRequest memory req = JoinPoolRequest({
                assets: poolAssets,
                maxAmountsIn: maxAmountsIn,
                userData: "",
                fromInternalBalance: false
            });
            IBalancerVault(balancerVaultAddress).joinPool(
                balancerLPPool,
                address(this),
                address(this),
                req
            );
        }

        // Update last earned block
        lastEarnBlock = block.number;

        // Farm Want tokens obtained
        _farm();
    }
}
