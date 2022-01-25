// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./helpers/ReentrancyGuard.sol";

import "./helpers/Pausable.sol";

import "./helpers/Ownable.sol";

import "./interfaces/IERC20.sol";

import "./libraries/SafeERC20.sol";

import "./interfaces/IWBNB.sol";

import "./interfaces/IAMMRouter01.sol";

import "./interfaces/IAMMRouter02.sol";

import "./libraries/SafeMath.sol";

abstract contract VaultBase is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* State */
    // TODO: Check to make sure these are all set
    bool public isCOREStaking; // If true, is for staking just core token of AMM (e.g. CAKE for Pancakeswap, BANANA for Apeswap, etc.)
    bool public isSameAssetDeposit; // Same asset token (not LP pair) TODO: Check for understanding with single staking vaults
    bool public isZorroComp; // This vault is for compounding. If true, will trigger farming/unfarming on earn events

    address public farmContractAddress; // Address of farm, e.g.: MasterChef (Pancakeswap) or MasterApe (Apeswap) contract
    uint256 public pid; // Pid of pool in farmContractAddress (e.g. the LP pool)
    address public wantAddress; // Address of contract that represents the staked token (e.g. PancakePair Contract / LP token on Pancakeswap)
    address public token0Address; // Address of first (or only) token
    address public token1Address; // Address of second token in pair if applicable
    address public token2Address; // Address of third token in pair if applicable
    address public token3Address; // Address of fourth token in pair if applicable TODO: Ensure these are in constructor
    address public earnedAddress; // Address of token that rewards are denominated in from farmContractAddress contract (e.g. CAKE token for Pancakeswap)
    address public tokenUSDCAddress; // USDC token address TODO: put this in constructor
    address public uniRouterAddress; // Router contract address for adding/removing liquidity, etc.
    address public uniPoolAddress; // Address of LP Pool address (e.g. PancakeV2Pair) TODO

    address public wbnbAddress; // Address of WBNB token (used to wrap BNB)
    address public zorroControllerAddress; // Address of ZorroController contract
    address public ZORROAddress; // Address of Zorro ERC20 token
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

    // Other
    // Ledger of Want tokens held by user when making deposits/withdrawals
    mapping(address => uint256) public wantTokensInHolding;

    /* Events */

    event SetSettings(
        uint256 _entranceFeeFactor,
        uint256 _withdrawFeeFactor,
        uint256 _controllerFee,
        uint256 _buyBackRate,
        uint256 _slippageFactor
    );
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
        require(
            _entranceFeeFactor >= entranceFeeFactorLL,
            "_entranceFeeFactor too low"
        );
        require(
            _entranceFeeFactor <= entranceFeeFactorMax,
            "_entranceFeeFactor too high"
        );
        entranceFeeFactor = _entranceFeeFactor;

        // Withdrawal fee
        require(
            _withdrawFeeFactor >= withdrawFeeFactorLL,
            "_withdrawFeeFactor too low"
        );
        require(
            _withdrawFeeFactor <= withdrawFeeFactorMax,
            "_withdrawFeeFactor too high"
        );
        withdrawFeeFactor = _withdrawFeeFactor;

        // Controller (performance) fee
        require(_controllerFee <= controllerFeeUL, "_controllerFee too high");
        controllerFee = _controllerFee;

        // Buyback + LP
        require(_buyBackRate <= buyBackRateUL, "_buyBackRate too high");
        buyBackRate = _buyBackRate;

        // Slippage tolerance
        require(
            _slippageFactor <= slippageFactorUL,
            "_slippageFactor too high"
        );
        slippageFactor = _slippageFactor;

        // Emit event with new settings
        emit SetSettings(
            _entranceFeeFactor,
            _withdrawFeeFactor,
            _controllerFee,
            _buyBackRate,
            _slippageFactor
        );
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
    function setBurnAddress(address _burnAddress) public virtual onlyAllowGov {
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
        // TODO: Rather than calling getAmountsOut(), try to take in an input arg instead
        uint256[] memory amounts = IAMMRouter02(_uniRouterAddress)
            .getAmountsOut(_amountIn, _path);
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

    /* Performance fees & buyback */

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
            IERC20(earnedAddress).safeIncreaseAllowance(
                uniRouterAddress,
                buyBackAmt
            );
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
    function distributeFees(uint256 _earnedAmt)
        internal
        virtual
        returns (uint256)
    {
        if (_earnedAmt > 0) {
            // If the Earned token amount is > 0, assess a controller fee, if the controller fee is > 0
            if (controllerFee > 0) {
                // Calculate the fee from the controllerFee parameters
                uint256 fee = _earnedAmt.mul(controllerFee).div(
                    controllerFeeMax
                );
                // Transfer the fee to the rewards address
                IERC20(earnedAddress).safeTransfer(rewardsAddress, fee);
                // Decrement the Earned token amount by the fee
                _earnedAmt = _earnedAmt.sub(fee);
            }
        }

        return _earnedAmt;
    }

    /* Abstract methods */

    // Deposits
    function exchangeUSDForWantToken(
        address _account,
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) public virtual returns (uint256);

    function depositWantToken(address _account, uint256 _wantAmt)
        public
        virtual
        returns (uint256);

    // Withdrawals
    function withdrawWantToken(address _account, uint256 _wantAmt)
        public
        virtual
        returns (uint256);

    function exchangeWantTokenForUSD(
        address _account,
        uint256 _amount,
        uint256 _maxMarketMovementAllowed
    ) public virtual returns (uint256);

    // Compounding
    function earn(uint256 _maxMarketMovementAllowed) public virtual;
}
