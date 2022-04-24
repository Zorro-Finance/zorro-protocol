// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerBase.sol";

import "../interfaces/IVault.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

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
    using CustomMath for uint256;
    using SafeSwapUni for IAMMRouter02;
    using PriceFeed for AggregatorV3Interface;

    /* Structs */
    struct WithdrawalResult {
        uint256 wantAmt; // Amount of Want token withdrawn
        uint256 mintedZORRewards; // ZOR rewards minted (to be burned XChain)
        uint256 rewardsDueXChain; // ZOR rewards due to the origin (cross chain) user
        uint256 slashedRewardsXChain; // Amount of ZOR rewards to be slashed (and thus rewarded to ZOR stakers)
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

        // Safely allow this contract to transfer the Want token from the sender to the underlying Vault contract
        pool.want.safeIncreaseAllowance(address(this), _wantAmt);

        // Transfer the Want token from the user to the Vault contract
        IERC20Upgradeable(pool.want).safeTransferFrom(
            msg.sender,
            pool.vault,
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

    /// @notice Internal function for depositing Want tokens into Vault
    /// @dev Because the vault entry date can be backdated, this is a dangerous method and should only be called indirectly through other functions
    /// @param _pid index of pool
    /// @param _account address of on-chain user (required for onchain, optional for cross-chain)
    /// @param _foreignAccount address of origin chain user (for cross chain transactions it's required)
    /// @param _wantAmt how much Want token to deposit (must already be sent to vault contract)
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

        // Associate foreign and local account address, as applicable

        // Get local chain account, as applicable
        address _localAccount = _account;
        if (_account == address(0)) {
            // Foreign account MUST be provided
            require(
                _foreignAccount.length > 0,
                "Neither foreign acct nor local acct provided"
            );
            // If no local account provided, truncate foreign chain address to 20-bytes
            _localAccount = address(bytes20(_foreignAccount));
        }

        // Perform the actual deposit function on the underlying Vault contract and get the number of shares to add
        uint256 sharesAdded = IVault(poolInfo[_pid].vault).depositWantToken(
            _localAccount,
            _wantAmt
        );
        // Determine time multiplier value. Set to 1e12 if the vault is the Zorro staking vault (because we don't do time multipliers on this vault)
        uint256 timeMultiplier = 1e12;
        if (pool.vault != zorroStakingVault) {
            // Determine the time multiplier value based on the duration committed to in weeks
            timeMultiplier = getTimeMultiplier(_weeksCommitted);
        }
        // Determine the individual user contribution based on the quantity of tokens to stake and the time multiplier
        uint256 contributionAdded = getUserContribution(
            sharesAdded,
            timeMultiplier
        );
        // Increment the pool's total contributions by the contribution added
        pool.totalTrancheContributions = pool.totalTrancheContributions.add(
            contributionAdded
        );
        // Update the reward debt that the user owes by multiplying user share % by the pool's accumulated Zorro rewards
        uint256 newTrancheShare = contributionAdded.mul(1e12).div(
            pool.totalTrancheContributions
        );

        // Create tranche info
        TrancheInfo memory _trancheInfo = TrancheInfo({
            contribution: contributionAdded,
            timeMultiplier: timeMultiplier,
            rewardDebt: pool.accZORRORewards.mul(newTrancheShare).div(1e12),
            durationCommittedInWeeks: _weeksCommitted,
            enteredVaultAt: _enteredVaultAt,
            exitedVaultAt: 0
        });
        _updateTrancheInfoForDeposit(
            _pid,
            _localAccount,
            _foreignAccount,
            _trancheInfo
        );

        // Emit deposit event
        emit Deposit(_localAccount, _foreignAccount, _pid, _wantAmt);
    }

    /// @notice Internal function for updating tranche ledger upon deposit
    /// @param _pid Index of pool
    /// @param _localAccount On-chain address
    /// @param _foreignAccount Cross-chain address, if applicable
    /// @param _trancheInfo TrancheInfo object
    function _updateTrancheInfoForDeposit(
        uint256 _pid,
        address _localAccount,
        bytes memory _foreignAccount,
        TrancheInfo memory _trancheInfo
    ) internal {
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

        // Approve spending of USDC (from user to this contract)
        IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(
            address(this),
            _valueUSDC
        );
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
        IVault vault = IVault(vaultAddr);

        // Exchange USDC for Want token in the Vault contract
        uint256 _wantAmt = vault.exchangeUSDForWantToken(
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
            _harvestOnly
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
    /// @return _res A WithdrawalResult struct containing relevant withdrawal result parameters
    function _withdraw(
        uint256 _pid,
        address _localAccount,
        bytes memory _foreignAccount,
        uint256 _trancheId,
        bool _harvestOnly
    ) internal returns (WithdrawalResult memory _res) {
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
        _res.mintedZORRewards = updatePool(_pid);

        // Withdraw pending ZORRO rewards (a.k.a. "Harvest")
        uint256 _trancheShare = _tranche.contribution.mul(1e12).div(
            _pool.totalTrancheContributions
        );
        uint256 _pendingRewards = _trancheShare
            .mul(_pool.accZORRORewards)
            .div(1e12)
            .sub(_tranche.rewardDebt);
        if (_pendingRewards > 0) {
            // If pending rewards payable, pay them out
            (uint256 _rewardsDue, uint256 _slashedRewards) = _getPendingRewards(
                _tranche,
                _pendingRewards
            );
            if (chainId == homeChainId) {
                // Simply transfer on-chain
                // Transfer ZORRO rewards to user, net of any applicable slashing
                if (_rewardsDue > 0) {
                    _safeZORROTransfer(_localAccount, _rewardsDue);
                }
                // Transfer any slashed rewards to single Zorro staking vault, if applicable
                if (_slashedRewards > 0) {
                    // Transfer slashed rewards to vault to reward ZORRO stakers
                    _safeZORROTransfer(zorroStakingVault, _slashedRewards);
                }
            } else {
                // Burn rewards due and slashed rewards, as we will be taking the equivalent amounts from the public pool on the home chain instead
                _safeZORROTransfer(
                    burnAddress,
                    _rewardsDue.add(_slashedRewards)
                );
                _res.rewardsDueXChain = _rewardsDue;
                _res.slashedRewardsXChain = _slashedRewards;
            }
        }

        // If not just harvesting (withdrawing too), proceed with below
        if (!_harvestOnly) {
            // Perform the actual withdrawal function on the underlying Vault contract and get the number of shares to remove
            IVault(poolInfo[_pid].vault).withdrawWantToken(
                _localAccount,
                _tranche.contribution
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
            trancheInfo[_pid][_localAccount][_trancheId].exitedVaultAt = block
                .timestamp;

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
        if (_localAccount == address(0)) {
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

    /// @notice Prepares values for paying out rewards
    /// @param _tranche TrancheInfo object
    /// @param _pendingRewards Qty of ZOR tokens as pending rewards
    /// @return _rewardsDue The amount of ZOR rewards payable
    /// @return _slashedRewards The amount of ZOR rewards slashed due to early withdrawals
    function _getPendingRewards(
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
        uint256 timeRemainingInCommitment = _tranche
            .enteredVaultAt
            .add(_tranche.durationCommittedInWeeks.mul(1 weeks))
            .sub(block.timestamp);
        if (timeRemainingInCommitment > 0) {
            _slashedRewards = _pendingRewards
                .mul(timeRemainingInCommitment)
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
        (uint256 _amountUSDC, , , ) = _withdrawalFullService(
            msg.sender,
            "",
            _pid,
            _trancheId,
            _harvestOnly,
            _maxMarketMovement
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
    /// @return _mintedZORRewards Amount of ZOR rewards minted (to be burned XChain)
    /// @return _rewardsDueXChain Amount of ZOR rewards due to the origin (cross chain) user
    /// @return _slashedRewardsXChain Amount of ZOR rewards to be slashed (and thus rewarded to ZOR stakers)
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
        returns (
            uint256 _amountUSDC,
            uint256 _mintedZORRewards,
            uint256 _rewardsDueXChain,
            uint256 _slashedRewardsXChain
        )
    {}

    /// @notice Private function for withdrawing funds from a pool and converting the Want token into USDC
    /// @param _account address of wallet on-chain
    /// @param _foreignAccount address of wallet cross-chain (that originally made this deposit)
    /// @param _pid index of pool to deposit into
    /// @param _trancheId index of tranche
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    /// @return _amountUSDC Amount of USDC withdrawn
    /// @return _mintedZORRewards Amount of ZOR rewards minted (to be burned XChain)
    /// @return _rewardsDueXChain Amount of ZOR rewards due to the origin (cross chain) user
    /// @return _slashedRewardsXChain Amount of ZOR rewards to be slashed (and thus rewarded to ZOR stakers)
    function _withdrawalFullService(
        address _account,
        bytes memory _foreignAccount,
        uint256 _pid,
        uint256 _trancheId,
        bool _harvestOnly,
        uint256 _maxMarketMovement
    )
        internal
        returns (
            uint256 _amountUSDC,
            uint256 _mintedZORRewards,
            uint256 _rewardsDueXChain,
            uint256 _slashedRewardsXChain
        )
    {
        // Get Vault contract
        address _vaultAddr = poolInfo[_pid].vault;
        IVault vault = IVault(_vaultAddr);

        // Call core withdrawal function (returns actual amount withdrawn)
        WithdrawalResult memory _res = _withdraw(
            _pid,
            _account,
            _foreignAccount,
            _trancheId,
            _harvestOnly
        );

        // Safe increase spending of Vault contract for Want token
        IERC20Upgradeable(poolInfo[_pid].want).safeIncreaseAllowance(
            _vaultAddr,
            _res.wantAmt
        );

        // Exchange Want for USD
        _amountUSDC = vault.exchangeWantTokenForUSD(
            _res.wantAmt,
            _maxMarketMovement
        );

        _mintedZORRewards = _res.mintedZORRewards;
        _rewardsDueXChain = _res.rewardsDueXChain;
        _slashedRewardsXChain = _res.slashedRewardsXChain;
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
        (uint256 withdrawnUSDC, , , ) = _withdrawalFullService(
            msg.sender,
            "",
            _fromPid,
            _fromTrancheId,
            false,
            _maxMarketMovement
        );
        // Redeposit
        address[] memory sourceTokens;
        sourceTokens[0] = defaultStablecoin;
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
        uint256 numTranches = trancheLength(_pid, msg.sender);
        for (uint256 tid = 0; tid < numTranches; ++tid) {
            withdraw(_pid, tid, false);
        }
    }

    /* Allocations */

    /// @notice Calculate time multiplier based on duration committed
    /// @param durationInWeeks number of weeks committed into Vault
    /// @return multiplier factor, times 1e12
    function getTimeMultiplier(uint256 durationInWeeks)
        public
        view
        returns (uint256)
    {
        if (isTimeMultiplierActive) {
            // Use sqrt(x * 10000)/100 to get better float point accuracy (see tests)
            return
                ((durationInWeeks.mul(1e4)).sqrt())
                    .mul(1e12)
                    .mul(2)
                    .div(1000)
                    .add(1e12);
        } else {
            return 1e12;
        }
    }

    /// @notice The contribution of the user, meant to be used in rewards allocations
    /// @param _liquidityCommitted How many tokens staked (e.g. LP tokens)
    /// @param _timeMultiplier Time multiplier value (from getTimeMultiplier())
    /// @return uint256 The relative contribution of the user (unitless)
    function getUserContribution(
        uint256 _liquidityCommitted,
        uint256 _timeMultiplier
    ) public pure returns (uint256) {
        return _liquidityCommitted.mul(_timeMultiplier).div(1e12);
    }
}
