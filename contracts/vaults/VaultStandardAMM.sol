// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/utils/Address.sol";

import "../interfaces/IAMMFarm.sol";

import "../interfaces/IAMMRouter02.sol";

import "./_VaultBase.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../libraries/SafeSwap.sol";


/// @title VaultStandardAMM: abstract base class for all PancakeSwap style AMM contracts. Maximizes yield in AMM.
contract VaultStandardAMM is VaultBase {
    /* Libraries */
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeSwapUni for IAMMRouter02;

    /* Constructor */

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
        govAddress = _addresses[0];
        zorroControllerAddress = _addresses[1];
        ZORROAddress = _addresses[2];

        wantAddress = _addresses[3];
        token0Address = _addresses[4];
        token1Address = _addresses[5];
        earnedAddress = _addresses[6];

        farmContractAddress = _addresses[7];
        pid = _pid;
        isCOREStaking = _isCOREStaking;
        isSameAssetDeposit = _isSameAssetDeposit;
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

        transferOwnership(zorroControllerAddress);
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _account The address of the end user account making the deposit
    /// @param _wantAmt The amount of Want token to deposit (must already be transferred)
    /// @return Number of shares added
    function depositWantToken(address _account, uint256 _wantAmt)
        public
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

    /// @notice Performs necessary operations to convert USDC into Want token and transfer back to sender
    /// @param _amountUSDC The amount of USDC to exchange for Want token (must already be deposited on this contract)
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

        // Swap USDC for token0
        address[] memory USDCToToken0Path;
        USDCToToken0Path[0] = tokenUSDCAddress;
        USDCToToken0Path[1] = token0Address;
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amountUSDC.div(2),
            _maxMarketMovementAllowed,
            USDCToToken0Path,
            address(this),
            block.timestamp.add(600)
        );

        // Swap USDC for token1 (if applicable)
        address[] memory USDCToToken1Path;
        USDCToToken1Path[0] = tokenUSDCAddress;
        USDCToToken1Path[1] = token1Address;
        IAMMRouter02(uniRouterAddress).safeSwap(
            _amountUSDC.div(2),
            _maxMarketMovementAllowed,
            USDCToToken1Path,
            address(this),
            block.timestamp.add(600)
        );

        // Deposit token0, token1 into LP pool to get Want token (i.e. LP token)
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        IERC20(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );
        IERC20(token1Address).safeIncreaseAllowance(
            uniRouterAddress,
            token1Amt
        );
        IAMMRouter02(uniRouterAddress).addLiquidity(
            token0Address,
            token1Address,
            token0Amt,
            token1Amt,
            token0Amt.mul(_maxMarketMovementAllowed).div(1000),
            token1Amt.mul(_maxMarketMovementAllowed).div(1000),
            address(this),
            block.timestamp.add(600)
        );

        // TODO: Account for pool with only one token

        // Calculate resulting want token balance
        uint256 _wantAmt = IERC20(wantAddress).balanceOf(address(this));

        // Transfer back to sender
        IERC20(wantAddress).safeTransfer(zorroControllerAddress, _wantAmt);

        return _wantAmt;
    }

    /// @notice Public function for farming Want token.
    function farm() public nonReentrant {
        _farm();
    }

    /// @notice Internal function for farming Want token. Responsible for staking Want token in a MasterChef/MasterApe-like contract
    function _farm() internal {
        // Farming should only occur if this contract is set for autocompounding
        require(isZorroComp, "!isZorroComp");

        // Get the Want token stored on this contract
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        // Increment the total Want tokens locked into this contract
        wantLockedTotal = wantLockedTotal.add(wantAmt);
        // Allow the farm contract (e.g. MasterChef/MasterApe) the ability to transfer up to the Want amount
        IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, wantAmt);

        if (isCOREStaking) {
            // If this contract is meant for staking a core asset of the underlying protocol (e.g. CAKE on Pancakeswap, BANANA on Apeswap),
            // Stake that token in a single-token-staking vault on the Farm contract
            IAMMFarm(farmContractAddress).enterStaking(wantAmt);
        } else {
            // Otherwise deposit the Want tokens in the Farm contract for the appropriate pool ID (PID)
            IAMMFarm(farmContractAddress).deposit(pid, wantAmt);
        }
    }

    /// @notice Internal function for unfarming Want token. Responsible for unstaking Want token from MasterChef/MasterApe contracts
    /// @param _wantAmt the amount of Want tokens to withdraw. If 0, will only harvest and not withdraw
    function _unfarm(uint256 _wantAmt) internal {
        if (isCOREStaking) {
            // If this is contract is meant for staking a core assets of the underlying protocol,
            // simply un-stake the asset from the single-token-staking vault on the Farm contract
            IAMMFarm(farmContractAddress).leaveStaking(_wantAmt); // Just for CAKE staking, we dont use withdraw()
        } else {
            // Otherwise simply withdraw the Want tokens from the Farm contract pool
            IAMMFarm(farmContractAddress).withdraw(pid, _wantAmt);
        }
    }

    /// @notice Fully withdraw Want tokens from the Farm contract (100% withdrawals only)
    /// @param _account address of user
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @return The number of shares removed
    function withdrawWantToken(address _account, bool _harvestOnly)
        public
        onlyZorroController
        nonReentrant
        whenNotPaused
        override
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

    /// @notice Converts Want token back into USD to be ready for withdrawal, transfers back to sender
    /// @param _amount The Want token quantity to exchange
    /// @param _maxMarketMovementAllowed The max slippage allowed for swaps. 1000 = 0 %, 995 = 0.5%, etc.
    /// @return Amount of USDC token obtained
    function exchangeWantTokenForUSD(
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) public virtual override onlyZorroController whenNotPaused returns (uint256) {
        // TODO: Too many local variables. Consolidate after uncommenting below
        // TODO: Take in current market prices (oracle)

        // Exit LP pool 
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

        // Swap token1 for USDC
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

        // TODO - account for pool with only one token

        uint256 amountUSDC = IERC20(tokenUSDCAddress).balanceOf(address(this));

        // Transfer back to sender
        IERC20(tokenUSDCAddress).safeTransfer(msg.sender, amountUSDC);

        return amountUSDC;
    }

    /// @notice The main compounding (earn) function. Reinvests profits since the last earn event.
    /// @param _maxMarketMovementAllowed The max slippage allowed. 1000 = 0 %, 995 = 0.5%, etc.
    function earn(uint256 _maxMarketMovementAllowed) public override nonReentrant whenNotPaused {
        // TODO: Take in price oracle to perform safe swaps
        // Only to be run if this contract is configured for auto-comnpounding
        require(isZorroComp, "!isZorroComp");
        // If onlyGov is set to true, only allow to proceed if the current caller is the govAddress
        if (onlyGov) {
            require(msg.sender == govAddress, "!gov");
        }

        // Harvest farm tokens
        _unfarm(0);

        // Get the balance of the Earned token on this contract (CAKE, BANANA, etc.)
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        // Reassign value of earned amount after distributing fees
        earnedAmt = _distributeFees(earnedAmt);
        // Reassign value of earned amount after buying back a certain amount of Zorro and sharing revenue w/ ZOR stakeholders
        earnedAmt = _buyBackAndRevShare(earnedAmt);

        // If staking a single token (CAKE, BANANA), farm that token and exit
        if (isCOREStaking || isSameAssetDeposit) {
            // Update the last earn block
            lastEarnBlock = block.number;
            _farm();
            return;
        }

        // Approve the router contract
        IERC20(earnedAddress).safeApprove(uniRouterAddress, 0);
        // Allow the router contract to spen up to earnedAmt
        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            earnedAmt
        );

        // Swap Earned token to token0 if token0 is not the Earned token
        if (earnedAddress != token0Address) {
            // Swap half earned to token0
            IAMMRouter02(uniRouterAddress).safeSwap(
                earnedAmt.div(2),
                slippageFactor,
                earnedToToken0Path,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Swap Earned token to token1 if token0 is not the Earned token
        if (earnedAddress != token1Address) {
            // Swap half earned to token1
            IAMMRouter02(uniRouterAddress).safeSwap(
                earnedAmt.div(2),
                slippageFactor,
                earnedToToken1Path,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Get values of tokens 0 and 1
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        // Provided that token0 and token1 are both > 0, add liquidity
        if (token0Amt > 0 && token1Amt > 0) {
            // Increase the allowance of the router to spend token0
            IERC20(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );
            // Increase the allowance of the router to spend token1
            IERC20(token1Address).safeIncreaseAllowance(
                uniRouterAddress,
                token1Amt
            );
            // Add liquidity
            IAMMRouter02(uniRouterAddress).addLiquidity(
                token0Address,
                token1Address,
                token0Amt,
                token1Amt,
                token0Amt.mul(_maxMarketMovementAllowed).div(1000),
                token1Amt.mul(_maxMarketMovementAllowed).div(1000),
                address(this),
                block.timestamp.add(600)
            );
        }

        // Update last earned block
        lastEarnBlock = block.number;

        // Farm Want token
        _farm();
    }
}
