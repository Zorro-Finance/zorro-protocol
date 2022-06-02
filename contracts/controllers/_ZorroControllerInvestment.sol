// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerBase.sol";

import "../interfaces/IVault.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SignedSafeMathUpgradeable.sol";

import "../libraries/Math.sol";

import "../libraries/SafeSwap.sol";

import "../libraries/PriceFeed.sol";

import "../interfaces/IZorroController.sol";

contract ZorroControllerInvestment is
    IZorroControllerInvestment,
    ZorroControllerBase
{
    /* Libraries */
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;
    using SignedSafeMathUpgradeable for int256;
    using CustomMath for uint256;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /* Structs */
    struct WithdrawalResult {
        uint256 wantAmt; // Amount of Want token withdrawn
        uint256 rewardsDueXChain; // ZOR rewards due to the origin (cross chain) user
    }

    /* State */

    // Rewards
    bool public isTimeMultiplierActive; // If true, allows use of time multiplier
    // Zorro LP pool
    address public zorroLPPool; // Main pool for Zorro liquidity
    address public zorroLPPoolOtherToken; // For the dominant LP pool, the counterparty token to the ZOR token
    // Swaps
    address public uniRouterAddress; // Router contract address for adding/removing liquidity, etc.
    address[] public USDCToZorroPath; // The path to swap USDC to ZOR
    address[] public USDCToZorroLPPoolOtherTokenPath; // The router path from USDC to the primary Zorro LP pool, Token 0
    // Oracles
    AggregatorV3Interface public priceFeedZOR;
    AggregatorV3Interface public priceFeedLPPoolOtherToken;
    // Cross chain
    address public zorroXChainEndpoint; // Cross chain controller contract

    /* Modifiers */

    /// @notice Only allow sender to be the cross chain controller contract
    modifier onlyZorroXChain() {
        require(_msgSender() == zorroXChainEndpoint, "xchain only");
        _;
    }

    /* Setters */

    /// @notice Setter: Set time multiplier
    /// @param _isActive Whether it shall be active. If false, timemultiplier will be 1.
    function setIsTimeMultiplierActive(bool _isActive) external onlyOwner {
        isTimeMultiplierActive = _isActive;
    }

    /// @notice Setter: Zorro LP Pool params
    /// @param _zorroLPPool Address of the Zorro-X LP pool
    /// @param _zorroLPPoolOtherToken Address of the counterpart token to the ZOR token in the LP Pool
    function setZorroLPPoolParams(
        address _zorroLPPool,
        address _zorroLPPoolOtherToken
    ) external onlyOwner {
        zorroLPPool = _zorroLPPool;
        zorroLPPoolOtherToken = _zorroLPPoolOtherToken;
    }

    /// @notice Setter: Uniswap-compatible router address
    /// @param _uniV2Router Address of router
    function setUniRouter(address _uniV2Router) external onlyOwner {
        uniRouterAddress = _uniV2Router;
    }

    /// @notice Setter: Set path for token swap from USDC to ZOR
    /// @param _path Swap path
    function setUSDCToZORPath(address[] memory _path) external onlyOwner {
        USDCToZorroPath = _path;
    }

    /// @notice Setter: Set path for token swap from USDC to counterparty token in ZOR LP pool
    /// @param _path Swap path
    function setUSDCToZorroLPPoolOtherTokenPath(address[] memory _path)
        external
        onlyOwner
    {
        USDCToZorroLPPoolOtherTokenPath = _path;
    }

    /// @notice Setter: Chainlink price feeds
    /// @param _priceFeedZOR The address of the price feed for ZOR
    /// @param _priceFeedLPPoolOtherToken The address of the price feed for the counterparty token in the ZOR LP Pool
    function setPriceFeeds(
        address _priceFeedZOR,
        address _priceFeedLPPoolOtherToken
    ) external onlyOwner {
        priceFeedZOR = AggregatorV3Interface(_priceFeedZOR);
        priceFeedLPPoolOtherToken = AggregatorV3Interface(
            _priceFeedLPPoolOtherToken
        );
    }

    /// @notice Setter: Cross chain endpoint
    /// @param _contract Contract address of endpoint
    function setZorroXChainEndpoint(address _contract) external onlyOwner {
        zorroXChainEndpoint = _contract;
    }

    /* Events */

    event Deposit(
        address indexed account,
        bytes indexed foreignAccount,
        uint256 indexed pid,
        uint256 wantAmount
    );

    event Withdraw(
        address indexed account,
        bytes indexed foreignAccount,
        uint256 indexed pid,
        uint256 trancheId,
        uint256 wantAmount
    );
    event TransferInvestment(
        address account,
        uint256 indexed fromPid,
        uint256 indexed fromTrancheId,
        uint256 indexed toPid
    );

    /* Cash flow */

    /// @notice Deposit Want tokens to associated Vault
    /// @param _pid index of pool
    /// @param _wantAmt how much Want token to deposit
    /// @param _weeksCommitted how many weeks the user is committing to on this vault
    function deposit(
        uint256 _pid,
        uint256 _wantAmt,
        uint256 _weeksCommitted
    ) public nonReentrant {
        // Get pool info
        PoolInfo storage pool = poolInfo[_pid];

        // Transfer the Want token from the user to the this contract
        IERC20Upgradeable(pool.want).safeTransferFrom(
            msg.sender,
            address(this),
            _wantAmt
        );

        // Call core deposit function
        _deposit(
            _pid,
            msg.sender,
            "",
            _wantAmt,
            _weeksCommitted,
            block.timestamp
        );
    }

    /// @notice Deposits tokens into Vault, updates poolInfo and trancheInfo ledgers
    /// @dev Because the vault entry date can be backdated, this is a dangerous method and should only be accessed indirectly through other functions
    /// @param _pid index of pool
    /// @param _account address of on-chain user (required for onchain, optional for cross-chain)
    /// @param _foreignAccount address of origin chain user (for cross chain transactions it's required)
    /// @param _wantAmt how much Want token to deposit (must already be sent to the vault)
    /// @param _weeksCommitted how many weeks the user is committing to on this vault
    /// @param _enteredVaultAt Date to backdate vault entry to
    /// @return _mintedZORRewards Amount of ZOR rewards minted
    function _deposit(
        uint256 _pid,
        address _account,
        bytes memory _foreignAccount,
        uint256 _wantAmt,
        uint256 _weeksCommitted,
        uint256 _enteredVaultAt
    ) internal returns (uint256 _mintedZORRewards) {
        // Get pool info
        PoolInfo storage pool = poolInfo[_pid];

        // Preflight checks
        require(_wantAmt > 0, "_wantAmt must be > 0!");

        // Update the pool before anything to ensure rewards have been updated and transferred
        _mintedZORRewards = updatePool(_pid);

        // Get local chain account, as applicable
        address _localAccount = _getLocalAccount(_account, _foreignAccount);

        // Allowance
        IERC20Upgradeable(pool.want).safeIncreaseAllowance(
            pool.vault,
            _wantAmt
        );

        // Perform the actual deposit function on the underlying Vault contract and get the number of shares to add
        uint256 sharesAdded = IVault(poolInfo[_pid].vault).depositWantToken(
            _localAccount,
            _wantAmt
        );

        // Determine time multiplier value.
        uint256 _timeMultiplier = getTimeMultiplier(_weeksCommitted);

        // Determine the individual user contribution based on the quantity of tokens to stake and the time multiplier
        uint256 _contributionAdded = _getUserContribution(
            sharesAdded,
            _timeMultiplier
        );

        // Update pool info: Increment the pool's total contributions by the contribution added
        pool.totalTrancheContributions = pool.totalTrancheContributions.add(
            _contributionAdded
        );

        // Create tranche
        _createTranche(
            _pid,
            _localAccount,
            _foreignAccount,
            _contributionAdded,
            _timeMultiplier,
            _weeksCommitted,
            _enteredVaultAt
        );

        // Emit deposit event
        emit Deposit(_localAccount, _foreignAccount, _pid, _wantAmt);
    }

    // TODO: test
    function _getLocalAccount(address _account, bytes memory _foreignAccount)
        private
        pure
        returns (address localAccount)
    {
        // Default to provided address if applicable
        localAccount = _account;

        // Otherwise try to extract from foreign account
        if (_account == address(0)) {
            // Foreign account MUST be provided
            require(
                _foreignAccount.length > 0,
                "Neither foreign acct nor local acct provided"
            );
            // If no local account provided, truncate foreign chain address to 20-bytes
            localAccount = address(bytes20(_foreignAccount));
        }
    }

    // TODO: test, and docstrings need to be updated
    /// @notice Internal function for updating tranche ledger upon deposit
    /// @param _pid Index of pool
    /// @param _localAccount On-chain address
    /// @param _foreignAccount Cross-chain address, if applicable
    /// @param _timeMultiplier Time multiplier factor for rewards
    /// @param _durationCommittedInWeeks Commitment in weeks for time multiplier
    /// @param _enteredVaultAt Timestamp at which entered vault
    function _createTranche(
        uint256 _pid,
        address _localAccount,
        bytes memory _foreignAccount,
        uint256 _contributionAdded,
        uint256 _timeMultiplier,
        uint256 _durationCommittedInWeeks,
        uint256 _enteredVaultAt
    ) internal {
        // Get pool
        PoolInfo memory pool = poolInfo[_pid];

        // Create tranche info
        TrancheInfo memory _trancheInfo = TrancheInfo({
            contribution: _contributionAdded, // Contribution including time multiplier
            timeMultiplier: _timeMultiplier,
            rewardDebt: pool.accZORRORewards.mul(_contributionAdded).div(
                pool.totalTrancheContributions
            ), // Pro-rata share of accumulated pool rewards, time-commitment weighted
            durationCommittedInWeeks: _durationCommittedInWeeks,
            enteredVaultAt: _enteredVaultAt,
            exitedVaultAt: 0
        });

        // Push a new tranche for this on-chain user
        trancheInfo[_pid][_localAccount].push(_trancheInfo);

        // If foreign account provided, write the tranche info to the foreign account ledger as well
        if (_foreignAccount.length > 0) {
            foreignTrancheInfo[_pid][_foreignAccount][
                trancheLength(_pid, _localAccount).sub(1)
            ] = _localAccount;
        }
    }

    /// @notice Deposits funds in a full service manner (performs autoswaps and obtains Want tokens)
    /// @param _pid index of pool to deposit into
    /// @param _valueUSDC value in USDC (in ether units) to deposit
    /// @param _weeksCommitted how many weeks to commit to the Pool (can be 0 or any uint)
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    function depositFullService(
        uint256 _pid,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement
    ) public nonReentrant {
        // Get Pool, Vault contract
        address vaultAddr = poolInfo[_pid].vault;

        // Safe transfer to Vault contract
        IERC20Upgradeable(defaultStablecoin).safeTransferFrom(
            msg.sender,
            vaultAddr,
            _valueUSDC
        );

        // Run core full deposit
        _depositFullService(
            _pid,
            msg.sender,
            "",
            _valueUSDC,
            _weeksCommitted,
            block.timestamp,
            _maxMarketMovement
        );
    }

    /// @notice Full service deposit function to be called by ZorroControllerXChain only.
    /// @param _pid index of pool to deposit into
    /// @param _account address of user on-chain
    /// @param _foreignAccount the cross chain wallet that initiated this call, if applicable.
    /// @param _valueUSDC value in USDC (in ether units) to deposit
    /// @param _weeksCommitted how many weeks to commit to the Pool (can be 0 or any uint)
    /// @param _vaultEnteredAt date that the vault was entered at
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    function depositFullServiceFromXChain(
        uint256 _pid,
        address _account,
        bytes memory _foreignAccount,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _vaultEnteredAt,
        uint256 _maxMarketMovement
    ) public onlyZorroXChain {
        // Get Pool, Vault contract
        address vaultAddr = poolInfo[_pid].vault;

        // Safe transfer to Vault contract
        IERC20Upgradeable(defaultStablecoin).safeTransferFrom(
            msg.sender,
            vaultAddr,
            _valueUSDC
        );

        // Make deposit full service call
        _depositFullService(
            _pid,
            _account,
            _foreignAccount,
            _valueUSDC,
            _weeksCommitted,
            _vaultEnteredAt,
            _maxMarketMovement
        );
    }

    /// @notice Private function for depositing
    /// @dev Dangerous method, as vaultEnteredAt can be backdated
    /// @param _pid index of pool to deposit into
    /// @param _account address of user on-chain
    /// @param _foreignAccount the cross chain wallet that initiated this call, if applicable.
    /// @param _valueUSDC value in USDC (in ether units) to deposit
    /// @param _weeksCommitted how many weeks to commit to the Pool (can be 0 or any uint)
    /// @param _vaultEnteredAt date that the vault was entered at
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    function _depositFullService(
        uint256 _pid,
        address _account,
        bytes memory _foreignAccount,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _vaultEnteredAt,
        uint256 _maxMarketMovement
    ) internal {
        // Get Pool, Vault contract
        address vaultAddr = poolInfo[_pid].vault;

        // Exchange USDC for Want token in the Vault contract
        uint256 _wantAmt = IVault(vaultAddr).exchangeUSDForWantToken(
            _valueUSDC,
            _maxMarketMovement
        );

        // Safe increase allowance and xfer Want to vault contract
        IERC20Upgradeable(poolInfo[_pid].want).safeIncreaseAllowance(
            vaultAddr,
            _wantAmt
        );

        // Make deposit
        // Call core deposit function
        _deposit(
            _pid,
            _account,
            _foreignAccount,
            _wantAmt,
            _weeksCommitted,
            _vaultEnteredAt
        );
    }

    /// @notice Fully withdraw Want tokens from underlying Vault.
    /// @param _pid index of pool
    /// @param _trancheId index of tranche
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @return Amount of Want token withdrawn
    function withdraw(
        uint256 _pid,
        uint256 _trancheId,
        bool _harvestOnly
    ) public nonReentrant returns (uint256) {
        // Withdraw Want token
        WithdrawalResult memory _res = _withdraw(
            _pid,
            msg.sender,
            "",
            _trancheId,
            _harvestOnly,
            false
        );

        // Transfer to user and return Want amount
        IERC20Upgradeable(poolInfo[_pid].want).safeTransfer(
            msg.sender,
            _res.wantAmt
        );

        return _res.wantAmt;
    }

    /// @notice Internal function for withdrawing Want tokens from underlying Vault.
    /// @dev Can only specify one of _localAccount, _foreignAccount
    /// @param _pid index of pool
    /// @param _localAccount Address of the on-chain account that the investment was made with
    /// @param _foreignAccount Address of the foreign chain account that this inviestment was made with
    /// @param _trancheId index of tranche
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @param _xChainRepatriation Intended for repatriation to another chain
    /// @return _res A WithdrawalResult struct containing relevant withdrawal result parameters
    function _withdraw(
        uint256 _pid,
        address _localAccount,
        bytes memory _foreignAccount,
        uint256 _trancheId,
        bool _harvestOnly,
        bool _xChainRepatriation
    ) internal returns (WithdrawalResult memory _res) {
        // TODO: Consider making WithdrwalResult an event instead?
        // Can only specify one account (on-chain/foreign, but not both)
        require(
            (_localAccount == address(0) && _foreignAccount.length > 0) ||
                (_localAccount != address(0) && _foreignAccount.length == 0),
            "Only one account type allowed"
        );
        // Determine account type and associated values
        TrancheInfo memory _tranche = _getTranche(
            _pid,
            _trancheId,
            _foreignAccount,
            _localAccount
        );

        // Get pool and current tranche info
        PoolInfo storage _pool = poolInfo[_pid];

        // Require non-zero tranche contribution
        require(_tranche.contribution > 0, "tranche.contribution is 0");
        // Require non-zero overall tranche contribution
        require(
            _pool.totalTrancheContributions > 0,
            "totalTrancheContributions is 0"
        );
        // Require that tranche has not yet been exited
        require(_tranche.exitedVaultAt == 0, "Already exited vault");

        // Update the pool before anything to ensure rewards have been updated and transferred
        updatePool(_pid);

        // Get pending rewards
        uint256 _pendingRewards = (
            _tranche.contribution.mul(_pool.accZORRORewards).div(
                _pool.totalTrancheContributions
            )
        ).sub(_tranche.rewardDebt);

        // Withdraw pending ZORRO rewards (a.k.a. "Harvest")
        if (_pendingRewards > 0) {
            // If pending rewards payable, pay them out
            (uint256 _rewardsDue, uint256 _slashedRewards) = _getAdjustedRewards(
                _tranche,
                _pendingRewards
            );

            if (_xChainRepatriation) {
                // Update rewardsDueXChain
                _res.rewardsDueXChain = _rewardsDue;

                if (chainId == homeChainId) {
                    // If repatriating AND on home chain

                    // Transfer any slashed rewards to single Zorro staking vault, if applicable
                    if (_slashedRewards > 0) {
                        // Transfer slashed rewards to vault to reward ZORRO stakers
                        _safeZORROTransfer(zorroStakingVault, _slashedRewards);
                    }
                } else {
                    // If repatriating and NOT on home chain,

                    // Record slashed rewards for Oracle to pick up and burn the corresponding amount on the home chain
                    if (_slashedRewards > 0) {
                        _recordSlashedRewards(_slashedRewards);
                    }
                }
            } else {
                // Transfer ZORRO rewards to user, net of any applicable slashing
                if (_rewardsDue > 0) {
                    _safeZORROTransfer(_localAccount, _rewardsDue);
                }

                if (chainId == homeChainId) {
                    // If NOT repatriating AND on home chain

                    // Transfer any slashed rewards to single Zorro staking vault, if applicable
                    if (_slashedRewards > 0) {
                        // Transfer slashed rewards to vault to reward ZORRO stakers
                        _safeZORROTransfer(zorroStakingVault, _slashedRewards);
                    }
                } else {
                    // If NOT repatriating and NOT on home chain

                    // Record slashed rewards for Oracle to pick up and burn the corresponding amount on the home chain
                    if (_slashedRewards > 0) {
                        _recordSlashedRewards(_slashedRewards);
                    }
                }
            }
        }

        // If not just harvesting (withdrawing too), proceed with below
        if (!_harvestOnly) {
            // Perform the actual withdrawal function on the underlying Vault contract and get the number of shares to remove

            // Get local (on-chain) account
            address _resolvedLocalAcct = _getLocalAccount(
                _localAccount,
                _foreignAccount
            );

            // Withdraw the want token for this account
            IVault(poolInfo[_pid].vault).withdrawWantToken(
                _resolvedLocalAcct,
                _getOrigSharesDeposited(_tranche.contribution, _tranche.timeMultiplier)
            );

            // Update shares safely
            _pool.totalTrancheContributions = _pool
                .totalTrancheContributions
                .sub(_tranche.contribution);

            // Calculate Want token balance
            _res.wantAmt = IERC20Upgradeable(_pool.want).balanceOf(
                address(this)
            );

            // Mark tranche as exited
            trancheInfo[_pid][_resolvedLocalAcct][_trancheId]
                .exitedVaultAt = block.timestamp;

            // Emit withdrawal event and return want balance
            emit Withdraw(
                _localAccount,
                _foreignAccount,
                _pid,
                _trancheId,
                _res.wantAmt
            );
        }
    }

    /// @notice Get tranche based on tranche ID and account information
    /// @dev Takes into account potential cross chain identities
    /// @param _pid Pool ID
    /// @param _trancheId Tranche ID
    /// @param _foreignAccount Identity of the foreign account that the tranche might be associated with
    /// @param _localAccount Identity of the account on the local chain that the tranche might be associated with
    /// @return _tranche TrancheInfo object for the tranche found
    function _getTranche(
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _foreignAccount,
        address _localAccount
    ) internal view returns (TrancheInfo memory _tranche) {
        if (_localAccount != address(0)) {
            // On-chain withdrawal
            _tranche = trancheInfo[_pid][_localAccount][_trancheId];
        } else {
            // Cross-chain withdrawal
            address _ftLocalAcct = foreignTrancheInfo[_pid][_foreignAccount][
                _trancheId
            ];
            _tranche = trancheInfo[_pid][_ftLocalAcct][_trancheId];
        }
    }

    /// @notice Splits rewards into rewards due and slashed rewards (if early withdrawal)
    /// @param _tranche TrancheInfo object
    /// @param _pendingRewards Qty of ZOR tokens as pending rewards
    /// @return _rewardsDue The amount of ZOR rewards payable
    /// @return _slashedRewards The amount of ZOR rewards slashed due to early withdrawals
    function _getAdjustedRewards(
        TrancheInfo memory _tranche,
        uint256 _pendingRewards
    ) internal view returns (uint256 _rewardsDue, uint256 _slashedRewards) {
        // Only process rewards > 0
        if (_pendingRewards <= 0) {
            return (0, 0);
        }
        // Check if this is an early withdrawal
        // If so, slash the accumulated rewards proportionally to the % time remaining before maturity of the time commitment
        // If not, distribute rewards as normal
        int256 _timeRemainingInCommitment = int256(_tranche.enteredVaultAt)
            .add(int256(_tranche.durationCommittedInWeeks.mul(1 weeks)))
            .sub(int256(block.timestamp));
        if (_timeRemainingInCommitment > 0) {
            _slashedRewards = _pendingRewards
                .mul(uint256(_timeRemainingInCommitment))
                .div(_tranche.durationCommittedInWeeks.mul(1 weeks));
            _rewardsDue = _pendingRewards.sub(_slashedRewards);
        } else {
            _rewardsDue = _pendingRewards;
        }
    }

    /// @notice Withdraws funds from a pool and converts the Want token into USDC
    /// @param _pid index of pool to deposit into
    /// @param _trancheId index of tranche
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    /// @return Amount (in USDC) returned
    function withdrawalFullService(
        uint256 _pid,
        uint256 _trancheId,
        bool _harvestOnly,
        uint256 _maxMarketMovement
    ) public nonReentrant returns (uint256) {
        // Withdraw Want token
        (uint256 _amountUSDC, ) = _withdrawalFullService(
            msg.sender,
            "",
            _pid,
            _trancheId,
            _harvestOnly,
            _maxMarketMovement,
            false
        );

        // Send USDC funds back to sender
        IERC20Upgradeable(defaultStablecoin).safeTransfer(
            msg.sender,
            _amountUSDC
        );

        return _amountUSDC;
    }

    /// @notice Full service withdrawal to be called from authorized cross chain endpoint
    /// @param _account address of wallet on-chain
    /// @param _foreignAccount address of wallet cross-chain (that originally made this deposit)
    /// @param _pid index of pool to deposit into
    /// @param _trancheId index of tranche
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    /// @return _amountUSDC Amount of USDC withdrawn
    /// @return _rewardsDueXChain Amount of ZOR rewards due to the origin (cross chain) user
    function withdrawalFullServiceFromXChain(
        address _account,
        bytes memory _foreignAccount,
        uint256 _pid,
        uint256 _trancheId,
        bool _harvestOnly,
        uint256 _maxMarketMovement
    )
        public
        onlyZorroXChain
        returns (uint256 _amountUSDC, uint256 _rewardsDueXChain)
    {
        // Call withdrawal function on chain
        (_amountUSDC, _rewardsDueXChain) = _withdrawalFullService(
            _account,
            _foreignAccount,
            _pid,
            _trancheId,
            _harvestOnly,
            _maxMarketMovement,
            true
        );

        // Transfer USDC balance obtained to caller
        if (_amountUSDC > 0) {
            IERC20Upgradeable(defaultStablecoin).safeTransfer(
                msg.sender,
                _amountUSDC
            );
        }

        // Burn xchain ZOR rewards due before repatriating, if applicable. (They will be minted on opposite chain)
        if (_rewardsDueXChain > 0) {
            IERC20Upgradeable(ZORRO).safeTransfer(burnAddress, _rewardsDueXChain);
        }
    }

    /// @notice Private function for withdrawing funds from a pool and converting the Want token into USDC
    /// @param _account address of wallet on-chain
    /// @param _foreignAccount address of wallet cross-chain (that originally made this deposit)
    /// @param _pid index of pool to deposit into
    /// @param _trancheId index of tranche
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    /// @param _xChainRepatriation Intended for repatriation to another chain
    /// @return _amountUSDC Amount of USDC withdrawn
    /// @return _rewardsDueXChain Amount of ZOR rewards due to the origin (cross chain) user
    function _withdrawalFullService(
        address _account,
        bytes memory _foreignAccount,
        uint256 _pid,
        uint256 _trancheId,
        bool _harvestOnly,
        uint256 _maxMarketMovement,
        bool _xChainRepatriation
    ) internal returns (uint256 _amountUSDC, uint256 _rewardsDueXChain) {
        // Get Vault contract
        address _vaultAddr = poolInfo[_pid].vault;

        // Call core withdrawal function (returns actual amount withdrawn)
        WithdrawalResult memory _res = _withdraw(
            _pid,
            _account,
            _foreignAccount,
            _trancheId,
            _harvestOnly,
            _xChainRepatriation
        );

        // Safe increase spending of Vault contract for Want token
        IERC20Upgradeable(poolInfo[_pid].want).safeIncreaseAllowance(
            _vaultAddr,
            _res.wantAmt
        );

        // Exchange Want for USD
        _amountUSDC = IVault(_vaultAddr).exchangeWantTokenForUSD(
            _res.wantAmt,
            _maxMarketMovement
        );

        _rewardsDueXChain = _res.rewardsDueXChain;
    }

    /// @notice Transfer all assets from a tranche in one vault to a new vault (works on-chain only)
    /// @param _fromPid index of pool FROM
    /// @param _fromTrancheId index of tranche FROM
    /// @param _toPid index of pool TO
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    function transferInvestment(
        uint256 _fromPid,
        uint256 _fromTrancheId,
        uint256 _toPid,
        uint256 _maxMarketMovement
    ) public nonReentrant {
        // Get weeks committed and entered at
        uint256 weeksCommitted = trancheInfo[_fromPid][msg.sender][
            _fromTrancheId
        ].durationCommittedInWeeks;
        uint256 enteredVaultAt = trancheInfo[_fromPid][msg.sender][
            _fromTrancheId
        ].enteredVaultAt;

        // Withdraw
        (uint256 withdrawnUSDC, ) = _withdrawalFullService(
            msg.sender,
            "",
            _fromPid,
            _fromTrancheId,
            false,
            _maxMarketMovement,
            false
        );

        // Transfer funds to vault
        IERC20Upgradeable(defaultStablecoin).safeTransfer(
            poolInfo[_toPid].vault,
            withdrawnUSDC
        );

        // Redeposit
        _depositFullService(
            _toPid,
            msg.sender,
            "",
            withdrawnUSDC,
            weeksCommitted,
            enteredVaultAt,
            _maxMarketMovement
        );

        emit TransferInvestment(msg.sender, _fromPid, _fromTrancheId, _toPid);
    }

    /// @notice Withdraw the maximum number of Want tokens from a pool
    /// @param _pid index of pool
    function withdrawAll(uint256 _pid) public nonReentrant {
        // Iterate through all tranches for the current user and pool and withdraw
        uint256 numTranches = trancheLength(_pid, msg.sender);
        for (uint256 tid = 0; tid < numTranches; ++tid) {
            _withdraw(_pid, msg.sender, "", tid, false, false);
        }

        // Transfer balance as applicable
        uint256 _wantBal = IERC20Upgradeable(poolInfo[_pid].want).balanceOf(
            address(this)
        );
        if (_wantBal > 0) {
            IERC20Upgradeable(poolInfo[_pid].want).safeTransfer(
                msg.sender,
                _wantBal
            );
        }
    }

    /* X-chain rewards management */

    /// @notice Gets rewards and sends to the recipient of a cross chain withdrawal
    /// @param _rewardsDue The amount of rewards that need to be fetched and sent to the wallet
    /// @param _destination Wallet to send funds to
    function repatriateRewards(uint256 _rewardsDue, address _destination)
        public
        onlyZorroXChain
    {
        // Get rewards based on chain type
        if (chainId == homeChainId) {
            // On Home chain. Fetch rewards from public pool and send to wallet
            _fetchFundsFromPublicPool(_rewardsDue, _destination);
        } else {
            // On other chain. Mint ZORRO tokens and send to wallet
            IZorro(ZORRO).mint(_destination, _rewardsDue);
        }
    }

    /// @notice Called by oracle to account for ZOR rewards that were minted or slashed on other chains
    /// @dev Caller should call "reset" functions so that rewards aren't double-burned/allocated
    /// @param _totalMinted Total ZOR rewards minted across other chains at this moment
    /// @param _totalSlashed Total ZOR rewards slashed across other chains at this moment
    function handleAccXChainRewards(uint256 _totalMinted, uint256 _totalSlashed)
        public
        onlyAllowZorroControllerOracle
        onlyHomeChain
    {
        // Burn shares that were minted on other chains so that
        // the total tokens minted across all chains is constant
        IERC20Upgradeable(ZORRO).safeTransfer(
            burnAddress,
            _totalMinted.sub(_totalSlashed)
        );

        // Transfer slashed rewards from public pool to ZOR staking vault
        _fetchFundsFromPublicPool(_totalSlashed, zorroStakingVault);
    }

    /* Allocations */

    /// @notice Calculate time multiplier based on duration committed
    /// @dev For Zorro staking vault, returns 1e12 no matter what
    /// @param durationInWeeks number of weeks committed into Vault
    /// @return timeMultiplier Time multiplier factor, times 1e12
    function getTimeMultiplier(uint256 durationInWeeks)
        public
        view
        returns (uint256 timeMultiplier)
    {
        timeMultiplier = 1e12;

        if (isTimeMultiplierActive) {
            // Use sqrt(x * 10000)/100 to get better float point accuracy (see tests)
            timeMultiplier = ((durationInWeeks.mul(1e4)).sqrt())
                .mul(1e12)
                .mul(2)
                .div(1000)
                .add(1e12);
        }
    }

    /// @notice The contribution of the user, meant to be used in rewards allocations
    /// @param _liquidityCommitted How many tokens staked (e.g. LP tokens)
    /// @param _timeMultiplier Time multiplier value (from getTimeMultiplier())
    /// @return uint256 The relative contribution of the user (unitless)
    function _getUserContribution(
        uint256 _liquidityCommitted,
        uint256 _timeMultiplier
    ) internal pure returns (uint256) {
        return _liquidityCommitted.mul(_timeMultiplier).div(1e12);
    }

    /// @notice Extracts the original shares deposited by user, accounting for the time multiplier
    /// @param _contribution The tranche contribution
    /// @param _timeMultiplier The time multiplier factor (including 1e12 factor)
    function _getOrigSharesDeposited(
        uint256 _contribution,
        uint256 _timeMultiplier
    ) internal pure returns (uint256) {
        return _contribution.mul(1e12).div(_timeMultiplier);
    }
}
