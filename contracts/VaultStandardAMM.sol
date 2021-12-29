// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./helpers/ERC20.sol";

import "./libraries/Address.sol";

import "./libraries/SafeERC20.sol";

import "./libraries/EnumerableSet.sol";

import "./helpers/Ownable.sol";

import "./interfaces/IAMMFarm.sol";

import "./interfaces/IAMMRouter01.sol";

import "./interfaces/IAMMRouter02.sol";

import "./helpers/ReentrancyGuard.sol";

import "./helpers/Pausable.sol";

import "./interfaces/IWBNB.sol";

import "./interfaces/IERC20.sol";

import "./libraries/SafeMath.sol";


/// @title VaultStandardAMM: abstract base class for all PancakeSwap style AMM contracts. Maximizes yield in AMM.
abstract contract VaultStandardAMM is Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* State */

    bool public isCOREStaking; // If true, is for staking just core token of AMM (e.g. CAKE for Pancakeswap, BANANA for Apeswap, etc.)
    bool public isSameAssetDeposit; // Same asset token (not LP pair) TODO: Check for understanding with single staking vaults
    bool public isZorroComp; // This vault is for compounding. If true, will trigger farming/unfarming on earn events

    address public farmContractAddress; // Address of farm, e.g.: MasterChef (Pancakeswap) or MasterApe (Apeswap) contract
    uint256 public pid; // Pid of pool in farmContractAddress (e.g. the LP pool)
    address public wantAddress; // Address of contract that represents the staked token (e.g. PancakePair Contract / LP token on Pancakeswap)
    address public token0Address; // Address of first (or only) token
    address public token1Address; // Address of second token in pair if applicable
    address public earnedAddress; // Address of token that rewards are denominated in from farmContractAddress contract (e.g. CAKE token for Pancakeswap)
    address public uniRouterAddress; // Router contract address for adding/removing liquidity, etc.

    address public wbnbAddress; // Address of WBNB token (used to wrap BNB)
    address public zorroControllerAddress; // Address of ZorroController contract
    address public ZORROAddress;// Address of Zorro ERC20 token
    address public govAddress; // Timelock controller contract
    bool public onlyGov = true; // Enforce gov only access on certain functions

    uint256 public lastEarnBlock = 0; // Last recorded block for an earn() event
    uint256 public wantLockedTotal = 0; // Total Want tokens locked/staked for this Vault
    uint256 public sharesTotal = 0; // Total shares for this Vault

    // Controller fee - used to fund operations
    uint256 public controllerFee = 0; // Numerator for controller fee rate (100 = 1%)
    uint256 public constant controllerFeeMax = 10000; // Denominator for controller fee rate
    uint256 public constant controllerFeeUL = 300; // Upper limit on controller fee rate (3%)

    // Buyback - used to elevate scarcity of Zorro token
    uint256 public buyBackRate = 0; // Numerator for buyback ratio (100 = 1%)
    uint256 public constant buyBackRateMax = 10000; // Denominator for buyback ratio
    uint256 public constant buyBackRateUL = 800; // Upper limit on buyback rate (8%)
    address public burnAddress = 0x000000000000000000000000000000000000dEaD; // Address to send funds to, to burn them
    address public rewardsAddress; // The TimelockController RewardsDistributor contract

    // Entrance fee - goes to pool + prevents front-running
    uint256 public entranceFeeFactor = 9990; // 9990 results in a 0.1% deposit fee (1 - 9990/10000)
    uint256 public constant entranceFeeFactorMax = 10000; // Denominator of entrance fee factor
    uint256 public constant entranceFeeFactorLL = 9900; // 1.0% is the max entrance fee settable. LL = "lowerlimit"

    // Withdrawal fee - goes to pool
    uint256 public withdrawFeeFactor = 10000; // Numerator of withdrawal fee factor
    uint256 public constant withdrawFeeFactorMax = 10000; // Denominator of withdrawal fee factor
    uint256 public constant withdrawFeeFactorLL = 9900; // 1.0% is the max entrance fee settable. LL = lowerlimit

    uint256 public slippageFactor = 950; // 950 = 5% default slippage tolerance
    uint256 public constant slippageFactorUL = 995;

    // Swap routes
    address[] public earnedToZORROPath;
    address[] public earnedToToken0Path;
    address[] public earnedToToken1Path;
    address[] public token0ToEarnedPath;
    address[] public token1ToEarnedPath;

    /* Events */

    event SetSettings(uint256 _entranceFeeFactor, uint256 _withdrawFeeFactor, uint256 _controllerFee, uint256 _buyBackRate, uint256 _slippageFactor);
    event SetGov(address _govAddress);
    event SetOnlyGov(bool _onlyGov);
    event SetUniRouterAddress(address _uniRouterAddress);
    event SetBurnAddress(address _buyBackAddress);
    event SetRewardsAddress(address _rewardsAddress);

    /* Modifiers */

    modifier onlyAllowGov() {
        require(msg.sender == govAddress, "!gov");
        _;
    }

    /* Investment Actions */

    /// @notice Receives new deposits from user
    /// @param _wantAmt amount of Want token to deposit/stake
    /// @return Number of shares added
    function deposit(uint256 _wantAmt) public virtual onlyOwner nonReentrant whenNotPaused returns (uint256) {
        // Transfer Want token from current user to this contract
        IERC20(wantAddress).safeTransferFrom(
            address(msg.sender),
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

        if (isZorroComp) {
            // If this contract is meant for Autocompounding, start to farm the staked token
            _farm();
        } else {
            // Otherwise, simply increment the quantity of total Want tokens locked
            wantLockedTotal = wantLockedTotal.add(_wantAmt);
        }

        return sharesAdded;
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
    function _unfarm(uint256 _wantAmt) internal virtual {
        if (isCOREStaking) {
            // If this is contract is meant for staking a core assets of the underlying protocol, 
            // simply un-stake the asset from the single-token-staking vault on the Farm contract
            IAMMFarm(farmContractAddress).leaveStaking(_wantAmt); // Just for CAKE staking, we dont use withdraw()
        } else {
            // Otherwise simply withdraw the Want tokens from the Farm contract pool
            IAMMFarm(farmContractAddress).withdraw(pid, _wantAmt);
        }
    }

    /// @notice Withdraw Want tokens from the Farm contract
    /// @param _wantAmt the amount of Want tokens to withdraw
    /// @return the number of shares removed
    function withdraw(uint256 _wantAmt) public virtual onlyOwner nonReentrant returns (uint256) {
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

    // 2. Converts farm tokens into want tokens
    // 3. Deposits want tokens

    /// @notice The main compounding (earn) function. Reinvests profits since the last earn event. 
    function earn() public virtual nonReentrant whenNotPaused {
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

        // Get the balance of the Earned token on this contract (CAKE, BANANA, etc.)
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

        // Approve the router contract 
        IERC20(earnedAddress).safeApprove(uniRouterAddress, 0);
        // Allow the router contract to spen up to earnedAmt
        IERC20(earnedAddress).safeIncreaseAllowance(uniRouterAddress, earnedAmt);

        // Swap Earned token to token0 if token0 is not the Earned token
        if (earnedAddress != token0Address) {
            // Swap half earned to token0
            _safeSwap(
                uniRouterAddress,
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
            _safeSwap(
                uniRouterAddress,
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
                0,
                0,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Update last earned block
        lastEarnBlock = block.number;

        // Farm Want token
        _farm();
    }

    /// @notice buy back Zorro tokens, deposit them as liquidity, and burn the LP tokens (removing them from circulation and increasing scarcity)
    /// @param _earnedAmt The amount of Earned tokens (profit) to deposit as liquidity 
    /// @return the remaining earned token amount after buyback operations
    function buyBack(uint256 _earnedAmt) internal virtual returns (uint256) {
        // If the buyback rate is 0, return the _earnedAmt and exit
        if (buyBackRate <= 0) {
            return _earnedAmt;
        }
        // Calculate the buyback amount via the buyBackRate parameters
        uint256 buyBackAmt = _earnedAmt.mul(buyBackRate).div(buyBackRateMax);
        if (earnedAddress == ZORROAddress) {
            // If the Earned token is in fact the Zorro token, transfer the buyback amount to the burn address
            IERC20(earnedAddress).safeTransfer(burnAddress, buyBackAmt);
        } else {
            // Allow the router to spend the Earned token up to the buyback amount
            IERC20(earnedAddress).safeIncreaseAllowance(uniRouterAddress, buyBackAmt);
            // Swap the Earned token for the Zorro and send to the burn address
            _safeSwap(
                uniRouterAddress,
                buyBackAmt,
                slippageFactor,
                earnedToZORROPath,
                burnAddress,
                block.timestamp.add(600)
            );
        }

        // Return the Earned amount net of the buyback amount
        return _earnedAmt.sub(buyBackAmt);
    }

    /// @notice distribute controller (performance) fees
    /// @param _earnedAmt The Earned token amount (profits)
    /// @return The Earned token amount net of distributed fees
    function distributeFees(uint256 _earnedAmt) internal virtual returns (uint256) {
        if (_earnedAmt > 0) {
            // If the Earned token amount is > 0, assess a controller fee, if the controller fee is > 0
            if (controllerFee > 0) {
                // Calculate the fee from the controllerFee parameters
                uint256 fee = _earnedAmt.mul(controllerFee).div(controllerFeeMax);
                // Transfer the fee to the rewards address
                IERC20(earnedAddress).safeTransfer(rewardsAddress, fee);
                // Decrement the Earned token amount by the fee
                _earnedAmt = _earnedAmt.sub(fee);
            }
        }

        return _earnedAmt;
    }

    /* Maintenance Functions */

    /// @notice Converts dust tokens into earned tokens, which will be reinvested on the next earn()
    function convertDustToEarned() public virtual whenNotPaused {
        // Only proceed if the contract is meant for autocompounding and is NOT for single staking (CAKE, BANANA, etc.)
        require(isZorroComp, "!isZorroComp");
        require(!isCOREStaking, "isCOREStaking");

        // Converts token0 dust (if any) to earned tokens
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        if (token0Address != earnedAddress && token0Amt > 0) {
            IERC20(token0Address).safeIncreaseAllowance(
                uniRouterAddress,
                token0Amt
            );

            // Swap all dust tokens to earned tokens
            _safeSwap(
                uniRouterAddress,
                token0Amt,
                slippageFactor,
                token0ToEarnedPath,
                address(this),
                block.timestamp.add(600)
            );
        }

        // Converts token1 dust (if any) to earned tokens
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token1Address != earnedAddress && token1Amt > 0) {
            IERC20(token1Address).safeIncreaseAllowance(
                uniRouterAddress,
                token1Amt
            );

            // Swap all dust tokens to earned tokens
            _safeSwap(
                uniRouterAddress,
                token1Amt,
                slippageFactor,
                token1ToEarnedPath,
                address(this),
                block.timestamp.add(600)
            );
        }
    }

    /// @notice Pause contract
    function pause() public virtual onlyAllowGov {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() public virtual onlyAllowGov {
        _unpause();
    }

    /// @notice wrap BNB (public version, only callable by gov)
    function wrapBNB() public virtual onlyAllowGov {
        _wrapBNB();
    }
    
    /// @notice wrap BNB to WBNB
    function _wrapBNB() internal virtual {
        uint256 bnbBal = address(this).balance;
        if (bnbBal > 0) {
            IWBNB(wbnbAddress).deposit{value: bnbBal}();
        }
    }


    /* Configuration */

    /// @notice Configure key fee parameters
    /// @param _entranceFeeFactor Entrance fee numerator (higher means smaller percentage)
    /// @param _withdrawFeeFactor Withdrawal fee numerator (higher means smaller percentage)
    /// @param _controllerFee Controller fee numerator
    /// @param _buyBackRate Buy back rate fee numerator
    /// @param _slippageFactor Slippage factor fee numerator
    function setSettings(
        uint256 _entranceFeeFactor,
        uint256 _withdrawFeeFactor,
        uint256 _controllerFee,
        uint256 _buyBackRate,
        uint256 _slippageFactor
    ) public virtual onlyAllowGov {
        // Entrance fee
        require(_entranceFeeFactor >= entranceFeeFactorLL, "_entranceFeeFactor too low");
        require(_entranceFeeFactor <= entranceFeeFactorMax, "_entranceFeeFactor too high");
        entranceFeeFactor = _entranceFeeFactor;

        // Withdrawal fee
        require(_withdrawFeeFactor >= withdrawFeeFactorLL,"_withdrawFeeFactor too low");
        require(_withdrawFeeFactor <= withdrawFeeFactorMax,"_withdrawFeeFactor too high");
        withdrawFeeFactor = _withdrawFeeFactor;

        // Controller (performance) fee
        require(_controllerFee <= controllerFeeUL, "_controllerFee too high");
        controllerFee = _controllerFee;

        // Buyback + LP
        require(_buyBackRate <= buyBackRateUL, "_buyBackRate too high");
        buyBackRate = _buyBackRate;

        // Slippage tolerance
        require(_slippageFactor <= slippageFactorUL, "_slippageFactor too high");
        slippageFactor = _slippageFactor;

        // Emit event with new settings
        emit SetSettings(_entranceFeeFactor, _withdrawFeeFactor, _controllerFee, _buyBackRate, _slippageFactor);
    }

    /// @notice Set governor address
    /// @param _govAddress The new gov address
    function setGov(address _govAddress) public virtual onlyAllowGov {
        govAddress = _govAddress;
        emit SetGov(_govAddress);
    }

    /// @notice Set onlyGov property
    /// @param _onlyGov whether onlyGov should be enforced
    function setOnlyGov(bool _onlyGov) public virtual onlyAllowGov {
        onlyGov = _onlyGov;
        emit SetOnlyGov(_onlyGov);
    }

    /// @notice Set the address of the periphery/router contract (Pancakeswap/Apeswap/etc.)
    function setUniRouterAddress(address _uniRouterAddress)
        public
        virtual
        onlyAllowGov
    {
        uniRouterAddress = _uniRouterAddress;
        emit SetUniRouterAddress(_uniRouterAddress);
    }

    /// @notice Set the burn address (for removing tokens out of existence)
    /// @param _burnAddress the burn address
    function setBurnAddress(address _burnAddress)
        public
        virtual
        onlyAllowGov
    {
        burnAddress = _burnAddress;
        emit SetBurnAddress(_burnAddress);
    }

    /// @notice set the address of the contract to send controller fees to
    /// @param _rewardsAddress the address of the Rewards contract
    function setRewardsAddress(address _rewardsAddress)
        public
        virtual
        onlyAllowGov
    {
        rewardsAddress = _rewardsAddress;
        emit SetRewardsAddress(_rewardsAddress);
    }

    /* Safety Functions */

    /// @notice Safely transfer ERC20 tokens stuck in this contract to a specified address
    /// @param _token Address of the ERC20 token to transfer
    /// @param _amount The amount of the tokens to transfer
    /// @param _to The address to transfer tokens to
    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) public virtual onlyAllowGov {
        require(_token != earnedAddress, "!safe");
        require(_token != wantAddress, "!safe");
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /// @notice Safely swap tokens
    /// @param _uniRouterAddress The address of the AMM router contract
    /// @param _amountIn The quantity of the origin token to swap
    /// @param _slippageFactor The maximum slippage factor tolerated for this swap
    /// @param _path The path to take for the swap
    /// @param _to The destination to send the swapped token to
    /// @param _deadline How much time to allow for the transaction
    function _safeSwap(
        address _uniRouterAddress,
        uint256 _amountIn,
        uint256 _slippageFactor,
        address[] memory _path,
        address _to,
        uint256 _deadline
    ) internal virtual {
        uint256[] memory amounts = IAMMRouter02(_uniRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length.sub(1)];

        IAMMRouter02(_uniRouterAddress)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn,
            amountOut.mul(_slippageFactor).div(1000),
            _path,
            _to,
            _deadline
        );
    }
}
