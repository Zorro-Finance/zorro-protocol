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

import "./interfaces/ITranchessExchange.sol";

import "./interfaces/ITranchessFund.sol";

import "./interfaces/ITranchessBatchOperationHelper.sol";


/// @title Vault contract for Tranchess funds (covers all major tokens: Queen, Bishop, Rook, as well as funds: ETH, BTCB).
contract VaultTranchess is VaultBase {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* Constants */
    uint256 internal constant TRANCHE_M = 0;
    uint256 internal constant TRANCHE_A = 1;
    uint256 internal constant TRANCHE_B = 2;

    /* Constructor */
    // TODO: @param descriptions
    // TODO: Adjust these for tranchess
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

        // TODO
        /*
        - tranchessExchange = ?
        - trancheIndex = TRANCHE_M
        - tranchessFund = ?
        - batchOperationHelper = ?
        */
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

    /* Structs */
    struct PendingClaim {
        uint256 preSettlementAmount;
        address user;
    }

    /* State */

    address public constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address public tranchessExchange;
    address public tranchessFund;
    address public batchOperationHelper;
    uint256 public trancheIndex;

    // Pending claims by epoch. Mapping: epoch timestamp => array of PendingClaim objects
    mapping(uint256 => PendingClaim[]) public pendingClaims;
    mapping(uint256 => PendingClaim[]) public pendingClaimsUSDC;
    // Pending claims by user. Mapping: epoch timestamp => user => pre-settlement amount
    mapping(uint256 => mapping(address => uint256)) public pendingClaimsByUser;
    mapping(uint256 => mapping(address => uint256)) public pendingClaimsByUserUSDC;
    // Total claim amounts by epoch. Mapping: epoch timestamp => value of all preSettlement claim amounts
    mapping(uint256 => uint256) public totalClaimAmount;
    mapping(uint256 => uint256) public totalClaimAmountUSDC;
    // Settled amounts by epoch. Mapping: epoch timestamp => user => settled amount
    mapping(uint256 => mapping(address => uint256)) public settledAmounts;
    mapping(uint256 => mapping(address => uint256)) public settledAmountsUSDC;
    // Settled trades by epoch. Mapping: epoch timestamp => amount (0 if not settled yet)
    mapping(uint256 => uint256) public settledTrades;
    mapping(uint256 => uint256) public settledTradesUSDC;

    /* Investment Actions */

    /// @notice Transfers USDC from user wallet to get want token. Because trades are async until settlement, Want token amount is not known yet.
    /// @param _account The account to get the USDC from
    /// @param _amount The amount of USDC to deposit
    /// @param _maxMarketMovementAllowed Max premium/discount acceptable for trade to go through (See pdLevel calcs in _buy function in Exchange.sol in Tranchess contract for more info. Use the maxPDLevel as input here)
    /// @return amount of Want tokens obtained (or 0 if async), and whether the Want tokens are obtained synchrounously
    function exchangeUSDForWantToken(address _account, uint256 _amount, uint256 _maxMarketMovementAllowed) public nonReentrant whenNotPaused onlyOwner override returns (uint256, bool) {
      // Transfer USDC from account to this contract
      IERC20(USDC).safeTransferFrom(_account, address(this), _amount);

      // Get Tranchess exchange, fund
      ITranchessExchange exchange = ITranchessExchange(tranchessExchange);
      ITranchessFund fund = ITranchessFund(tranchessFund);

      // Get Tranchess rebalance version
      uint256 version = fund.getRebalanceSize();

      // Use the USDC to buy the Tranchess token (Queen, Bishop, Rook) via Swap (Fund). 
      // This will create a claim, as the trade will not settle yet
      if (trancheIndex == TRANCHE_M) {
        // Queen
        exchange.buyM(version, _maxMarketMovementAllowed, _amount);
      } else if (trancheIndex == TRANCHE_A) {
        // Rook
        exchange.buyA(version, _maxMarketMovementAllowed, _amount);
      } else if (trancheIndex == TRANCHE_B) {
        // Bishop
        exchange.buyB(version, _maxMarketMovementAllowed, _amount);
      } else {
        revert("Invalid Tranchess trancheIndex");
      }

      // Get end of current Tranchess swap epoch (30 min period)
      uint256 endEpoch = exchange.endOfEpoch(block.timestamp);

      // Record settlement info
      // Pending claims
      pendingClaims[endEpoch].push(PendingClaim({
          user: _account,
          preSettlementAmount: _amount
      }));
      pendingClaimsByUser[endEpoch][_account] = _amount;
      // Increment total claims
      totalClaimAmount[endEpoch] = totalClaimAmount[endEpoch] + _amount;

      return (0, false);
    }

    /// @notice Receives new deposits from user (assumes Want token is already on this contract)
    /// @dev NOTE: Very important: Unlike in synchronous Vault contracts (e.g. Pancake), this function MUST be called immediately when Want tokens are claimed, or else accounting will be off.
    /// @param _wantAmt amount of Want token to deposit/stake (e.g. Queen, Bishop, Rook) for the user of interest
    /// @return Number of shares added
    function depositWantToken(uint256 _wantAmt)
        public
        virtual
        onlyOwner
        nonReentrant
        whenNotPaused
        override
        returns (uint256)
    {
        // NOTE: As mentioned above, unlike other depositWantToken() functions, the one in this contract assumes that the Want token was 
        // already added to this contract. Thus there is no need to transfer funds from the calling contract to here.


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
            // _farm(); // No CHESS farming yet for this contract - coming soon!
        } else {
            // Otherwise, simply increment the quantity of total Want tokens locked
            wantLockedTotal = wantLockedTotal.add(_wantAmt);
        }

        return sharesAdded;
    }

    /// @notice Transfers USDC from user wallet to get want token. Because trades are async until settlement, Want token amount is not known yet.
    /// @param _account The account that is claiming the USDC
    /// @param _amount The amount of Want token to withdraw
    /// @param _maxMarketMovementAllowed Max premium/discount acceptable for trade to go through (See pdLevel calcs in _buy function in Exchange.sol in Tranchess contract for more info. Use the maxPDLevel as input here)
    /// @return amount of Want tokens obtained (or 0 if async), and whether the Want tokens are obtained synchrounously
    function exchangeWantTokenForUSD(address _account, uint256 _amount, uint256 _maxMarketMovementAllowed) public nonReentrant whenNotPaused onlyOwner override returns (uint256, bool) {
      // Get Tranchess exchange, fund
      ITranchessExchange exchange = ITranchessExchange(tranchessExchange);
      ITranchessFund fund = ITranchessFund(tranchessFund);

      // Get Tranchess rebalance version
      uint256 version = fund.getRebalanceSize();

      // Sell the Tranchess token (Queen, Bishop, Rook) via Swap (Fund) for USDC. 
      // This will create a claim, as the trade will not settle yet
      if (trancheIndex == TRANCHE_M) {
        // Queen
        exchange.sellM(version, _maxMarketMovementAllowed, _amount);
      } else if (trancheIndex == TRANCHE_A) {
        // Rook
        exchange.sellA(version, _maxMarketMovementAllowed, _amount);
      } else if (trancheIndex == TRANCHE_B) {
        // Bishop
        exchange.sellB(version, _maxMarketMovementAllowed, _amount);
      } else {
        revert("Invalid Tranchess trancheIndex");
      }

      // Get end of current Tranchess swap epoch (30 min period)
      uint256 endEpoch = exchange.endOfEpoch(block.timestamp);

      // Record settlement info
      // Pending claims
      pendingClaimsUSDC[endEpoch].push(PendingClaim({
          user: _account,
          preSettlementAmount: _amount
      }));
      pendingClaimsByUserUSDC[endEpoch][_account] = _amount;
      // Increment total claims
      totalClaimAmountUSDC[endEpoch] = totalClaimAmount[endEpoch] + _amount;

      return (0, false);
    }

    /// @notice Withdraw Want tokens from the Farm contract
    /// @dev NOTE: Very important: Unlike in synchronous Vault contracts (e.g. Pancake), this function MUST be called immediately when USDC tokens are claimed, or else accounting will be off.
    /// @param _wantAmt the amount of Want tokens to withdraw
    /// @return the number of shares removed
    function withdrawWantToken(uint256 _wantAmt)
        public
        virtual
        onlyOwner
        nonReentrant
        override
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
            // _unfarm(_wantAmt); // No CHESS farming yet for this contract - coming soon!
            // TODO Harvest earned Chess tokens pro-rata
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

    /// @notice Settle any outstanding trades on this contract for the specified epoch (idempotent)
    /// @dev NOTE: Important: Remember to call associated deposit/withdraw function in the same transaction immediately after calling this function, to prevent any accounting errors
    /// @dev NOTE: Important: Call this function in a batched transaction with all other users in the same epoch
    /// @param _user the address of the end user whose funds need to be settled
    /// @param _settlementEpoch the end of the epoch that the trades will have settled in
    /// @param _token The address of the token to settle
    /// @return amount of token returned from settlement
    function settleTrades(address _user, uint256 _settlementEpoch, address _token) public onlyOwner override returns (uint256) {
        // Init
        uint256 userShare;

        // Idempotency: If this epoch was already settled:
        if (settledTrades[_settlementEpoch] > 0) {
            // Check if user's share has been updated 
            if (settledAmounts[_settlementEpoch][_user] > 0) {
                // If yes, return that user's amount 
                return settledAmounts[_settlementEpoch][_user];
            } else {
                // If no, update that user's amount based on their share of the original quote and return that amount
                userShare = calcUserShareOfSettlement(settledTrades[_settlementEpoch], _settlementEpoch, _user);
                settledAmounts[_settlementEpoch][_user] = userShare;
                return userShare;
            }
        }

        // Get BatchOperationHelper
        ITranchessBatchOperationHelper batchOpHelper = ITranchessBatchOperationHelper(batchOperationHelper);

        // Get exchanges
        address[] memory exchanges;
        exchanges[0] = tranchessExchange;

        // Encode epochs
        uint256[] memory encodedEpochs;
        // First 32 bits are the exchange index. Next 32 are the maker/taker value. The rest (192) is the epoch value
        // exchangeIndex is 0x0;
        // makerTaker is 0x1; // 0 for maker, 1 for taker
        encodedEpochs[0] = 0x0<<256 | 0x1<<192 | _settlementEpoch;

        // Settle trades with tranchess to claim tokens
        (uint256[] memory totalTokenAmounts, uint256 totalQuoteAmount) = batchOpHelper.settleTrades(exchanges, encodedEpochs, address(this));
        uint256 amountClaimed;

        if (_token == USDC) {
            amountClaimed = totalQuoteAmount;
        } else {
            if (trancheIndex == TRANCHE_M) {
                // Queen
                amountClaimed = totalTokenAmounts[0];
            } else if (trancheIndex == TRANCHE_A) {
                // Rook
                amountClaimed = totalTokenAmounts[1];
            } else if (trancheIndex == TRANCHE_B) {
                // Bishop
                amountClaimed = totalTokenAmounts[2];
            } else {
                revert("Invalid Tranchess trancheIndex");
            }
        }

        // Update claims
        // Settled amounts (per user)
        userShare = calcUserShareOfSettlement(amountClaimed, _settlementEpoch, _user);
        settledAmounts[_settlementEpoch][_user] = userShare;
        // Settled trades (per epoch)
        settledTrades[_settlementEpoch] = amountClaimed;

        // Return amount of Want tokens or USDC (use settledAmounts variable)
        return userShare;
    }   

    /// @notice Calculate the given user's share of the claim, proportional to their pre-settlment contribution
    /// @param _claimableAmount The total amount of a token available from a claim
    /// @param _settlementEpoch Timestamp of the end of the epoch for settlement
    /// @param _user Address of the user claiming the token
    function calcUserShareOfSettlement(uint256 _claimableAmount, uint256 _settlementEpoch, address _user) internal view returns (uint256) {
        return  _claimableAmount.mul(pendingClaimsByUser[_settlementEpoch][_user]).div(totalClaimAmount[_settlementEpoch]);
    }

    /// @notice The main compounding (earn) function. Reinvests profits since the last earn event.
    function earn() public virtual nonReentrant whenNotPaused override {
        // No CHESS farming yet for this contract - coming soon!
    }
}
