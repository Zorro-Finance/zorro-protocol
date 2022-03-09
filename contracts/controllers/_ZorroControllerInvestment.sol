// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerBase.sol";

import "../interfaces/IVault.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../libraries/Math.sol";

import "../tokens/TokenLockController.sol";

import "../tokens/ZorroTokens.sol";

import "../interfaces/ICurveMetaPool.sol";

import "../libraries/SafeSwap.sol";


// TODO: VERY IMPORTANT: Once code is done, check all ABI encodings to make sure method signature string matches the order of all
// arguments. We changed around the order of many args.
// TODO: Do an overall audit of the code base to see where we should emit events. 
// TODO: onlyXChainEndpoints modifier may not be enough. Imagine scenario where someone makes a cross-chain call to revertXChainDeposit()
// but isn't authorized. We need to extract the cross-chain msg.sender to check. 


contract ZorroControllerInvestment is ZorroControllerBase {
    /* Libraries */
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using CustomMath for uint256;
    using SafeSwapCurve for ICurveMetaPool;
    using SafeSwapUni for IAMMRouter02;

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
        IERC20(pool.want).safeTransferFrom(msg.sender, pool.vault, _wantAmt);

        // Call core deposit function
        _deposit(_pid, msg.sender, _wantAmt, _weeksCommitted, block.timestamp);
    }

    /// @notice Internal function for depositing Want tokens into Vault
    /// @dev Because the vault entry date can be backdated, this is a dangerous method and should only be called indirectly through other functions
    /// @param _pid index of pool
    /// @param _user address of user
    /// @param _wantAmt how much Want token to deposit (must already be sent to vault contract)
    /// @param _weeksCommitted how many weeks the user is committing to on this vault
    /// @param _enteredVaultAt Date to backdate vault entry to
    function _deposit(
        uint256 _pid,
        address _user,
        uint256 _wantAmt,
        uint256 _weeksCommitted,
        uint256 _enteredVaultAt
    ) internal {
        // Get pool info
        PoolInfo storage pool = poolInfo[_pid];

        // Preflight checks
        require(_wantAmt > 0, "_wantAmt must be > 0!");

        // Update the pool before anything to ensure rewards have been updated and transferred
        updatePool(_pid);

        // Perform the actual deposit function on the underlying Vault contract and get the number of shares to add
        uint256 sharesAdded = IVault(poolInfo[_pid].vault).depositWantToken(
            _user,
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
        uint256 rewardDebt = pool.accZORRORewards.mul(newTrancheShare).div(
            1e12
        );
        // Push a new tranche for this user
        trancheInfo[_pid][_user].push(
            TrancheInfo({
                contribution: contributionAdded,
                timeMultiplier: timeMultiplier,
                rewardDebt: rewardDebt,
                durationCommittedInWeeks: _weeksCommitted,
                enteredVaultAt: _enteredVaultAt,
                exitedVaultStartingAt: 0
            })
        );
        // Emit deposit event
        emit Deposit(_user, _pid, _wantAmt);
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
        IVault vault = IVault(vaultAddr);

        // Approve spending of USDC (from user to this contract)
        IERC20(defaultStablecoin).safeIncreaseAllowance(address(this), _valueUSDC);
        // Safe transfer to Vault contract
        IERC20(defaultStablecoin).safeTransferFrom(msg.sender, vaultAddr, _valueUSDC);

        // Run core full deposit 
        _depositFullService(
            _pid,
            msg.sender,
            _valueUSDC,
            _weeksCommitted,
            block.timestamp,
            _maxMarketMovement
        );
    }

    /// @notice Private function for depositing
    /// @dev Dangerous method, as vaultEnteredAt can be backdated
    /// @param _pid index of pool to deposit into
    /// @param _user address of user
    /// @param _valueUSDC value in USDC (in ether units) to deposit
    /// @param _weeksCommitted how many weeks to commit to the Pool (can be 0 or any uint)
    /// @param _vaultEnteredAt date that the vault was entered at
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    function _depositFullService(
        uint256 _pid,
        address _user,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _vaultEnteredAt,
        uint256 _maxMarketMovement
    ) internal {
        // Get Pool, Vault contract
        address vaultAddr = poolInfo[_pid].vault;
        IVault vault = IVault(vaultAddr);

        // Exchange USDC for Want token in the Vault contract
        uint256 wantAmt = vault.exchangeUSDForWantToken(_valueUSDC, _maxMarketMovement);

        // Transfer Want token back to Vault contract
        IERC20(poolInfo[_pid].want).safeTransfer(vaultAddr, wantAmt);

        // Make deposit
        // Call core deposit function
        _deposit(_pid, _user, wantAmt, _weeksCommitted, _vaultEnteredAt);
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
        uint256 _wantAmt = _withdraw(_pid, msg.sender, _trancheId, _harvestOnly);
        
        // Transfer to user and return Want amount
        IERC20(poolInfo[_pid].want).safeTransfer(msg.sender, _wantAmt);
        
        return _wantAmt;
    }

    /// @notice Internal function for withdrawing Want tokens from underlying Vault.
    /// @param _pid index of pool
    /// @param _trancheId index of tranche
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @return Amount of Want token withdrawn
    function _withdraw(
        uint256 _pid,
        address _user,
        uint256 _trancheId,
        bool _harvestOnly
    ) internal returns (uint256) {
        // Update the pool before anything to ensure rewards have been updated and transferred
        updatePool(_pid);

        // Get pool and current tranche info
        PoolInfo storage pool = poolInfo[_pid];
        TrancheInfo storage tranche = trancheInfo[_pid][_user][_trancheId];

        /* Preflight checks on contributions */
        require(tranche.contribution > 0, "tranche.contribution is 0");
        require(
            pool.totalTrancheContributions > 0,
            "totalTrancheContributions is 0"
        );

        // Withdraw pending ZORRO rewards (a.k.a. "Harvest")
        uint256 trancheShare = tranche.contribution.mul(1e12).div(
            pool.totalTrancheContributions
        );
        uint256 pendingRewards = trancheShare
            .mul(pool.accZORRORewards)
            .div(1e12)
            .sub(tranche.rewardDebt);
        if (pendingRewards > 0) {
            // Check if this is an early withdrawal
            // If so, slash the accumulated rewards proportionally to the % time remaining before maturity of the time commitment
            // If not, distribute rewards as normal
            uint256 oneWeek = 1 weeks;
            uint256 timeRemainingInCommitment = tranche
                .enteredVaultAt
                .add(tranche.durationCommittedInWeeks.mul(oneWeek))
                .sub(block.timestamp);
            uint256 rewardsDue = 0;
            uint256 slashedRewards = 0;
            if (timeRemainingInCommitment > 0) {
                slashedRewards = pendingRewards
                    .mul(timeRemainingInCommitment)
                    .div(tranche.durationCommittedInWeeks.mul(oneWeek));
                rewardsDue = pendingRewards.sub(slashedRewards);
            } else {
                rewardsDue = pendingRewards;
            }
            // Transfer ZORRO rewards to user, net of any applicable slashing
            safeZORROTransfer(_user, rewardsDue);
            // Transfer any slashed rewards to single Zorro staking vault, if applicable
            if (slashedRewards > 0) {
                address singleStakingVaultZORRO = poolInfo[_pid].vault;
                // Transfer slashed rewards to vault to reward ZORRO stakers
                safeZORROTransfer(singleStakingVaultZORRO, slashedRewards);
            }
        }

        // Perform the actual withdrawal function on the underlying Vault contract and get the number of shares to remove
        IVault(poolInfo[_pid].vault).withdrawWantToken(
            _user,
            _harvestOnly
        );

        // Update shares safely
        pool.totalTrancheContributions = pool.totalTrancheContributions.sub(
            tranche.contribution
        );
        
        // Calculate Want token balance
        uint256 _wantBal = IERC20(pool.want).balanceOf(address(this));

        // All withdrawals are full withdrawals so delete the tranche
        deleteTranche(_pid, _trancheId, _user);

        // Emit withdrawal event and return want balance
        emit Withdraw(_user, _pid, _trancheId, _wantBal);

        return _wantBal;
    }

    /// @notice Delete a tranche from a user's tranches
    /// @param _pid index of pool to deposit into
    /// @param _trancheId index of tranche
    /// @param _user User to remove tranche from
    function deleteTranche(
        uint256 _pid,
        uint256 _trancheId,
        address _user
    ) internal {
        // Determine the number of tranches
        uint256 _trancheLength = trancheInfo[_pid][_user].length;
        // Shift tranche to current index
        trancheInfo[_pid][_user][_trancheId] = trancheInfo[_pid][_user][
            _trancheLength - 1
        ];
        // Pop last item off of tranche array
        trancheInfo[_pid][_user].pop();
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
        uint256 _amountUSDC = _withdrawalFullService(
            msg.sender,
            _pid,
            _trancheId,
            _harvestOnly,
            _maxMarketMovement
        );

        // Send USDC funds back to sender
        IERC20(defaultStablecoin).safeTransfer(msg.sender, _amountUSDC);

        return _amountUSDC;
    }

    /// @notice Private function for withdrawing funds from a pool and converting the Want token into USDC
    /// @param _account address of user
    /// @param _pid index of pool to deposit into
    /// @param _trancheId index of tranche
    /// @param _harvestOnly If true, will only harvest Zorro tokens but not do a withdrawal
    /// @param _maxMarketMovement factor to account for max market movement/slippage. The definition varies by Vault, so consult the associated Vault contract for info
    /// @return Amount (in USDC) returned
    function _withdrawalFullService(
        address _account,
        uint256 _pid,
        uint256 _trancheId,
        bool _harvestOnly,
        uint256 _maxMarketMovement
    ) internal returns (uint256) {
        // Update tranche status
        trancheInfo[_pid][_account][_trancheId].exitedVaultStartingAt = block.timestamp;

        // Get Vault contract
        IVault vault = IVault(poolInfo[_pid].vault);

        // Call core withdrawal function (returns actual amount withdrawn)
        uint256 wantAmtWithdrawn = _withdraw(
            _pid,
            _account,
            _trancheId,
            _harvestOnly
        );

        // Transfer Want token to Vault contract
        IERC20(poolInfo[_pid].want).safeTransfer(poolInfo[_pid].vault, wantAmtWithdrawn);

        uint256 amount = vault.exchangeWantTokenForUSD(
            wantAmtWithdrawn,
            _maxMarketMovement
        );

        return amount;
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
        uint256 withdrawnUSDC = _withdrawalFullService(
            msg.sender,
            _fromPid,
            _fromTrancheId,
            true,
            _maxMarketMovement
        );
        // Redeposit
        address[] memory sourceTokens;
        sourceTokens[0] = defaultStablecoin;
        _depositFullService(
            _toPid,
            msg.sender,
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
            return
                (
                    uint256(1).add(
                        (uint256(2).div(10)).mul(durationInWeeks.sqrt())
                    )
                ).mul(1e12);
        } else {
            return 1e12;
        }
    }

    /// @notice The contribution of the user, meant to be used in rewards allocations
    /// @param _liquidityCommitted How many tokens staked (e.g. LP tokens)
    /// @param _timeMultiplier Time multiplier value (from getTimeMultiplier())
    /// @return The relative contribution of the user (unitless)
    function getUserContribution(
        uint256 _liquidityCommitted,
        uint256 _timeMultiplier
    ) public pure returns (uint256) {
        return _liquidityCommitted.mul(_timeMultiplier).div(1e12);
    }

    /* Cross Chain functions */

    /* Deposits */

    /// @notice Prepares and sends a cross chain deposit request. Takes care of necessary financial ops (transfer/locking USDC)
    /// @param _chainId The Zorro destination chain ID so that the request can be routed to the appropriate chain
    /// @param _destinationContract The address of the smart contract on the destination chain
    /// @param _payload The input payload for the destination function, encoded in bytes (EVM ABI or equivalent depending on chain)
    function sendXChainDepositRequest(
        uint256 _chainId,
        bytes calldata _destinationContract,
        bytes calldata _payload
    ) external nonReentrant {
        // Get endpoint contract that interfaces with the remote chain
        XChainEndpoint _endpointContract = XChainEndpoint(endpointContracts[_chainId]);
        // Extract amount of USDC to transfer into this contract from the payload
        uint256 _amountUSDC = _endpointContract.extractValueFromPayload(
            _payload
        );
        // Verify that encoded user identity is in fact msg.sender.
        address _userIdentity = _endpointContract.extractIdentityFromPayload(
            _payload
        );
        require(
            _userIdentity == msg.sender,
            "Payload sender doesnt match msg.sender"
        );
        // Allow this contract to spend USDC
        IERC20(defaultStablecoin).safeIncreaseAllowance(
            address(this),
            _amountUSDC
        );

        // TODO: Need to collect a xchain deposit fee here! And the net amount of the deposit needs to be accounted for somehow.

        // Transfer USDC into this contract
        IERC20(defaultStablecoin).safeTransferFrom(
            msg.sender,
            address(this),
            _amountUSDC
        );
        // Lock USDC on the ledger
        TokenLockController(lockUSDCController).lockFunds(
            msg.sender,
            _amountUSDC
        );
        // Call contract layer
        _endpointContract.sendXChainTransaction(
            _destinationContract, 
            _payload, 
            ""
        );
    }

    /// @notice Receives a cross chain deposit request from the contract layer of the XchainEndpoint contract
    /// @dev For params, see _depositFullService() function declaration above
    function receiveXChainDepositRequest(
        address _account,
        uint256 _valueUSDC,
        uint256 _pid,
        uint256 _weeksCommitted,
        uint256 _vaultEnteredAt,
        uint256 _maxMarketMovement
    ) external onlyXChainEndpoints {
        // Mint corresponding amount of zUSDC
        ZUSDC(syntheticStablecoin).mint(address(this), _valueUSDC);
        // Swap zUSDC for USDC
        ICurveMetaPool(curveStablePoolAddress).safeSwap(
            _valueUSDC,
            _maxMarketMovement,
            curveSyntheticStablecoinIndex,
            curveDefaultStablecoinIndex
        );
        // Call deposit function
        _depositFullService(
            _pid,
            _account,
            _valueUSDC,
            _weeksCommitted,
            _vaultEnteredAt,
            _maxMarketMovement
        );
    }

    /* Withdrawals */

    /// @notice Prepares and sends a cross chain withdrwal request.
    /// @param _chainId The Zorro destination chain ID so that the request can be routed to the appropriate chain
    /// @param _destinationContract The address of the smart contract on the destination chain
    /// @param _payload The input payload for the destination function, encoded in bytes (EVM ABI or equivalent depending on chain)
    function sendXChainWithdrawalRequest(
        uint256 _chainId,
        bytes calldata _destinationContract,
        bytes calldata _payload
    ) external nonReentrant {
        // Get endpoint contract that interfaces with the remote chain
        XChainEndpoint _endpointContract = XChainEndpoint(endpointContracts[_chainId]);
        // Verify that the encoded user identity is in fact msg.sender
        address _userIdentity = _endpointContract.extractIdentityFromPayload(
            _payload
        );
        require(
            _userIdentity == msg.sender,
            "Payload sender doesnt match msg.sender"
        );
        // Call contract layer
        _endpointContract.sendXChainTransaction(
            _destinationContract, 
            _payload, 
            ""
        );
    }

    /// @notice Receives a cross chain withdrawal request from the contract layer of the XchainEndpoint contract
    /// @dev For params, see _withdrawalFullService() function declaration above. Executes idempotently.
    function receiveXChainWithdrawalRequest(
        address _account,
        uint256 _chainId,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement
    ) external onlyXChainEndpoints {
        // First check if withdrawal was already attempted (e.g. there was a cross chain failure). If so, redrive this function
        // without the withdrawal and lock steps
        TrancheInfo memory tranche = trancheInfo[_pid][_account][_trancheId];
        uint256 _amountUSDC = 0;
        if (tranche.exitedVaultStartingAt == 0) {
            // Call withdrawal function
            _amountUSDC = _withdrawalFullService(
                _account,
                _pid,
                _trancheId,
                false,
                _maxMarketMovement
            );
            // Lock withdrawn USDC
            TokenLockController(lockUSDCController).lockFunds(
                _account,
                _amountUSDC
            );
        } else {
            // Lookup amount locked
            _amountUSDC = TokenLockController(lockUSDCController).lockedFunds(_account);
        }

        // Only proceed if there is something to withdraw
        require(_amountUSDC > 0, "Nothing to withdraw");

        // Prepare repatriation transaction
        bytes memory _destinationContract = abi.encodePacked(homeChainZorroController);
        bytes memory _payload = abi.encodeWithSignature(
            "receiveXChainRepatriationRequest(address _account,uint256 _withdrawnUSDC,uint256 _chainId,uint256 _pid,uint256 _trancheId,uint256 _maxMarketMovement,address _callbackContract)",
            _account,
            _amountUSDC,
            _chainId,
            _pid,
            _trancheId,
            _maxMarketMovement,
            address(this)
        );

        // Call contract layer to dispatch cross chain transaction
        XChainEndpoint _xChainEndpoint = XChainEndpoint(endpointContracts[homeChainId]);
        _xChainEndpoint.sendXChainTransaction(
            _destinationContract, 
            _payload, 
            ""
        );
    }

    /// @notice Receives a repatriation request from another chain and takes care of all financial operations (unlock/mint/burn) to pay the user their withdrawn funds from another chain
    /// @param _account The user on this chain who initiated the withdrawal request
    /// @param _withdrawnUSDC The amount of USDC withdrawn on the remote chain
    /// @param _chainId The Chain ID of the remote chain that initiated this request
    /// @param _originalNetDepositUSDC The amount originally deposited into this tranche, NET of fees
    /// @param _pid The pool ID on the remote chain that the user withdrew from
    /// @param _trancheId The ID of the tranche on the remote chain, that was originally used to deposit
    /// @param _maxMarketMovement factor to account for max market movement/slippage, expressed as numerator over 1000 (e.g. 950 => 950/1000 = 0.95 = 5% slippage)
    /// @param _callbackContract The remote contract that called this function.
    function receiveXChainRepatriationRequest(
        address _account,
        uint256 _withdrawnUSDC,
        uint256 _chainId,
        uint256 _originalNetDepositUSDC,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement,
        address _callbackContract
    ) external onlyXChainEndpoints nonReentrant {
        // TODO Need original deposit amount, which is stored on opposite chain. 
        // OR we maintain a xchain mapping on this chain by tranche
        // TODO: Why are pid, trancheId not being used here?

        // Initialize finance variables
        uint256 _profit = 0;
        uint256 _unlockableAmountUSDC = 0;
        uint256 _mintableAmountZUSDC = 0;
        uint256 _burnableAmountUSDC = 0;

        // Update amounts depending on whether investment was profitable
        if (_withdrawnUSDC >= _originalNetDepositUSDC) {
            // Profitable
            // Calculate profit amount if a profit was made
            _profit = _withdrawnUSDC.sub(_originalNetDepositUSDC);
            // Set the unlockable amount to the original deposit amount (principal) only
            _unlockableAmountUSDC = _originalNetDepositUSDC;
            // Set the mint amount to the proceeds.
            _mintableAmountZUSDC = _profit;
        } else {
            // Loss
            // Set the unlockable amount to the withdrawal amount
            _unlockableAmountUSDC = _withdrawnUSDC;
            // The burn amount to the loss amount
            _burnableAmountUSDC = _originalNetDepositUSDC.sub(_withdrawnUSDC);
        }

        // Unlock USDC principal
        TokenLockController(lockUSDCController).unlockFunds(
            _account,
            _unlockableAmountUSDC,
            address(this)
        );
        // Mint zUSDC (if applicable)
        if (_mintableAmountZUSDC > 0) {
            ZUSDC(syntheticStablecoin).mint(
                address(this),
                _mintableAmountZUSDC
            );
            // Swap zUSDC for USDC
            ICurveMetaPool(curveStablePoolAddress).safeSwap(
                _mintableAmountZUSDC,
                _maxMarketMovement,
                curveSyntheticStablecoinIndex,
                curveDefaultStablecoinIndex
            );
        }
        // Burn unused USDC (if applicable)
        if (_burnableAmountUSDC > 0) {
            IERC20(defaultStablecoin).safeTransfer(
                burnAddress,
                _burnableAmountUSDC
            );
        }
        // Transfer total USDC to wallet
        uint256 _balanceUSDC = IERC20(defaultStablecoin).balanceOf(
            address(this)
        );
        IERC20(defaultStablecoin).transfer(_account, _balanceUSDC);
        // Send cross-chain burn request for the USDC that has been temporarily locked on the opposite chain
        sendXChainUnlockRequest(
            _account, 
            _withdrawnUSDC, 
            _chainId, 
            abi.encodePacked(_callbackContract)
        );
    }

    /* Cross-chain unlocks */

    /// @notice Sends a request to the remote chain to unlock and burn temporarily withheld USDC. To be called after a successful withdrawal
    /// @dev Internal function, only to be called by receiveXChainRepatriationRequest()
    /// @param _account The address of the wallet (cross chain identity) to unlock funds for
    /// @param _amountUSDC The amount in USDC that should be unlocked and burned
    /// @param _chainId The Zorro destination chain ID so that the request can be routed to the appropriate chain
    /// @param _destinationContract The address of the contract on the remote chain to send the unlock request to
    function sendXChainUnlockRequest(
        address _account,
        uint256 _amountUSDC,
        uint256 _chainId,
        bytes memory _destinationContract
    ) internal {
        // Get endpoint contract
        address _endpointContract = endpointContracts[_chainId];

        // Prepare cross chain request
        (bool success, bytes memory data) = _endpointContract.call(
            abi.encodeWithSignature(
                "encodeUnlockRequest(address _account,uint256 _amountUSDC)",
                _account,
                _amountUSDC
            )
        );
        require(success, "Unsuccessful serialize unlock");
        bytes memory _payload = abi.decode(data, (bytes));

        // Call contract layer
        (bool success1, ) = _endpointContract.call(
            abi.encodeWithSignature(
                "sendXChainTransaction(bytes calldata _destinationContract,bytes calldata _payload)",
                _destinationContract,
                _payload
            )
        );
        // Require successful call
        require(success1, "Unsuccessful xchain unlock");
    }

    /// @notice Receives a request from home chain (BSC) to unlock and burn temporarily withheld USDC.
    /// @param _account The address of the wallet (cross chain identity) to unlock funds for
    /// @param _amountUSDC The amount in USDC that should be unlocked and burned
    function receiveXChainUnlockRequest(address _account, uint256 _amountUSDC)
        external onlyXChainEndpoints
    {
        // Get controller
        TokenLockController lockController = TokenLockController(
            lockUSDCController
        );
        // Unlock user funds & burn
        lockController.unlockFunds(_account, _amountUSDC, burnAddress);
    }

    /* Other Cross Chain */

    /// @notice Performs both buyback and rev share operations for either on-chain or cross-chain
    /// @param _pid The pool ID
    /// @param _earnedAddress The address of the ERC20 earned token to buy back
    /// @param _buybackAmount The amount of earned token to buyback
    /// @param _revShareAmount The amount of earned token to share as revenue to the ZOR staking vault
    /// @param _earnedToZORPath The router path for swapping from the Earn token to the ZOR token on BSC (home chain)
    /// @param _earnedToZORLPPoolToken0Path The router path for swapping from the Earn token to the primary Zorro LP Pool's 0th token
    /// @param _earnedToZORLPPoolToken1Path The router path for swapping from the Earn token to the primary Zorro LP Pool's 1st token
    function buyBackAndRevShare(
        uint256 _pid,
        address _earnedAddress,
        uint256 _buybackAmount, 
        uint256 _revShareAmount,
        address[] calldata _earnedToZORPath,
        address[] calldata _earnedToZORLPPoolToken0Path,
        address[] calldata _earnedToZORLPPoolToken1Path
    ) external onlyXChainEndpoints {
        // Get total earnings fees
        uint256 _totalEarningsFees = _buybackAmount.add(_revShareAmount);
        
        // Increase allowance of earned token, to this contract
        IERC20(_earnedAddress).safeIncreaseAllowance(
            address(this),
            _totalEarningsFees
        );

        // Transfer buyback amount to this contract
        IERC20(_earnedAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _totalEarningsFees
        );

        // Check to see if the controller contract is on the home chain (BSC)
        if (address(this) == homeChainZorroController) {
            // If on home chain, perform buyback logic as normal
            buybackOnChain(_earnedAddress, _buybackAmount, _earnedToZORLPPoolToken0Path, _earnedToZORLPPoolToken1Path);
            revShareOnChain(_earnedAddress, _earnedToZORPath, _revShareAmount);
        } else {
            // If on a foreign chain, send a cross chain request for LP + burn, and revenue sharing
            distributeEarningsXChain(_pid, _earnedAddress, _buybackAmount, _revShareAmount);
        }
    }

    /// @notice Buys back the earned token on-chain, swaps it to add liquidity to the ZOR pool, then burns the associated LP token
    /// @param _token The address of the token to buy back (usually the "Earn" token or USDC)
    /// @param _buybackAmount The amount of Earn token to buy back  
    /// @param _tokenToZORLPPoolToken0Path The router path for swapping from _token to the 0th token of the primary ZOR LP pool (usually ZOR)
    /// @param _tokenToZORLPPoolToken1Path The router path for swapping from _token to the 1st token of the primary ZOR LP pool
    function buybackOnChain(
        address _token,
        uint256 _buybackAmount,
        address[] memory _tokenToZORLPPoolToken0Path,
        address[] memory _tokenToZORLPPoolToken1Path
    ) internal {
        // Authorize spending beforehand
        IERC20(_token).safeIncreaseAllowance(
            uniRouterAddress,
            _buybackAmount
        );
        // Swap to Token 0
        IAMMRouter02(uniRouterAddress).safeSwap(
            _buybackAmount.div(2),
            defaultMaxMarketMovement,
            _tokenToZORLPPoolToken0Path,
            address(this),
            block.timestamp.add(600)
        );
        // Swap to Token 1
        IAMMRouter02(uniRouterAddress).safeSwap(
            _buybackAmount.div(2),
            defaultMaxMarketMovement,
            _tokenToZORLPPoolToken1Path,
            address(this),
            block.timestamp.add(600)
        );
        // Enter LP pool
        uint256 token0Amt = IERC20(zorroLPPoolToken0).balanceOf(address(this));
        uint256 token1Amt = IERC20(zorroLPPoolToken1).balanceOf(address(this));
        IERC20(_tokenToZORLPPoolToken0Path[0]).safeIncreaseAllowance(
            uniRouterAddress,
            token0Amt
        );
        IERC20(_tokenToZORLPPoolToken1Path[0]).safeIncreaseAllowance(
            uniRouterAddress,
            token1Amt
        );
        (, , uint256 _liquidity) = IAMMRouter02(uniRouterAddress)
            .addLiquidity(
                zorroLPPoolToken0,
                zorroLPPoolToken1,
                token0Amt,
                token1Amt,
                token0Amt.mul(defaultMaxMarketMovement).div(1000),
                token1Amt.mul(defaultMaxMarketMovement).div(1000),
                address(this),
                block.timestamp.add(600)
            );

        // Burn liquidity token obtained
        IERC20(zorroLPPool).safeTransfer(burnAddress, _liquidity);
    }

    /// @notice Sends the specified earnings amount as revenue share to ZOR stakers
    /// @param _token The address of the token to be rev-shared
    /// @param _tokenToZORPath The router path to swap _token to ZOR
    /// @param _revShareAmount The amount of Earn token to share as revenue with ZOR stakers
    function revShareOnChain(
        address _token,
        address[] memory _tokenToZORPath,
        uint256 _revShareAmount
    ) internal {
        // Authorize spending beforehand
        IERC20(_token).safeIncreaseAllowance(
            uniRouterAddress,
            _revShareAmount
        );

        // Swap to ZOR
        IAMMRouter02(uniRouterAddress).safeSwap(
            _revShareAmount,
            defaultMaxMarketMovement,
            _tokenToZORPath,
            zorroStakingVault,
            block.timestamp.add(600)
        );
    }

    /// @notice Prepares and sends an earnings distribution request cross-chain (back to the home chain)
    /// @param _pid The pool ID associated with the vault which experienced earnings
    /// @param _earnedAddress The address of the Earn token
    /// @param _buybackAmount The amount of earned token to buyback
    /// @param _revShareAmount The amount of earned token to share as revenue to the ZOR staking vault
    function distributeEarningsXChain(
        uint256 _pid,
        address _earnedAddress,
        uint256 _buybackAmount,
        uint256 _revShareAmount
    ) internal {
        // Check lock to see if anything is pending for this block and pool. If so, revert
        require(
            lockedEarningsStatus[block.number][_pid] == 0,
            "Xchain earnings lock pending"
        );
        
        // Swap earned token for USDC
        address[] memory _path;
        _path[0] = _earnedAddress;
        _path[1] = defaultStablecoin;
        IAMMRouter02(uniRouterAddress).safeSwap(
            _buybackAmount.add(_revShareAmount),
            defaultMaxMarketMovement,
            _path,
            address(this),
            block.timestamp.add(600)
        );
        // Lock USDC on a ledger for this block and pid, with status of pending
        uint256 _amountUSDC = IERC20(defaultStablecoin).balanceOf(
            address(this)
        );
        TokenLockController(lockUSDCController).lockFunds(
            address(this),
            _amountUSDC
        );
        lockedEarningsStatus[block.number][_pid] = 1;
        // Fetch xchain endpoint for home chain
        XChainEndpoint xChainEndpoint = XChainEndpoint(endpointContracts[homeChainId]);

        // Account for any previously failed earnings
        uint256 _totalOriginalEarningsFees = _buybackAmount.add(_revShareAmount);
        uint256 _amountBuybackUSDC = _amountUSDC.mul(_buybackAmount).div(_totalOriginalEarningsFees);
        uint256 _amountRevShareUSDC = _amountUSDC.sub(_amountBuybackUSDC);
        // Construct payload
        bytes memory _payload = abi.encodeWithSignature(
            "receiveXChainDistributionRequest(uint256 _chainId,bytes _callbackContract,uint256 _amountUSDCBuyback,uint256 _amountUSDCRevShare,uint256 _failedAmountUSDCBuyback,uint256 _failedAmountUSDCRevShare)",
            chainId,
            abi.encode(address(this)),
            _amountBuybackUSDC,
            _amountRevShareUSDC,
            failedLockedBuybackUSDC,
            failedLockedRevShareUSDC
        );
        // Revert payload: Upon failure, updates lock ledger to failed for this block and pool
        bytes memory _recoveryPayload = abi.encodeWithSignature(
            "recoverXChainFeeDist(uint256 _blockNumber,uint256 _pid,uint256 _amountBuybackUSDC,uint256 _amountRevShareUSDC)",
            block.number,
            _pid,
            _amountUSDC
        );
        // Call the LP and burn function on the home chain
        xChainEndpoint.sendXChainTransaction(
            abi.encodePacked(homeChainZorroController),
            _payload,
            _recoveryPayload
        );
    }


    /// @notice Receives an authorized request from remote chains to perform earnings fee distribution events, such as: buyback + LP + burn, and revenue share
    /// @param _chainId The ID of the chain that this request originated from
    /// @param _callbackContract Address of destination contract in bytes for the callback
    /// @param _amountUSDCBuyback The amount in USDC that should be minted for LP + burn
    /// @param _amountUSDCRevShare The amount in USDC that should be minted for revenue sharing with ZOR stakers
    /// @param _failedAmountUSDCBuyback The previously failed buyback amount that is being retried
    /// @param _failedAmountUSDCRevShare The previously failed revshare amount that is being retried
    function receiveXChainDistributionRequest(
        uint256 _chainId,
        bytes calldata _callbackContract,
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare,
        uint256 _failedAmountUSDCBuyback,
        uint256 _failedAmountUSDCRevShare
    ) external onlyXChainEndpoints {
        // Total USDC to perform operations
        uint256 _amountUSDC = _amountUSDCBuyback.add(_amountUSDCRevShare).add(_failedAmountUSDCBuyback).add(_failedAmountUSDCRevShare);

        // Mint zUSDC
        ZUSDC(syntheticStablecoin).mint(address(this), _amountUSDC);

        // Swap to USDC
        uint256 _amountZUSDC = IERC20(syntheticStablecoin).balanceOf(
            address(this)
        );
        ICurveMetaPool(curveStablePoolAddress).safeSwap(
            _amountZUSDC,
            defaultMaxMarketMovement,
            curveSyntheticStablecoinIndex,
            curveDefaultStablecoinIndex
        );
        // Determine new USDC balances
        uint256 _balUSDC = IERC20(defaultStablecoin).balanceOf(address(this));

        /* Buyback */
        uint256 _buybackAmount = _balUSDC.mul(_amountUSDCBuyback.add(_failedAmountUSDCBuyback)).div(_amountUSDC);
        buybackOnChain(defaultStablecoin, _buybackAmount, USDCToZorroLPPoolToken0Path, USDCToZorroLPPoolToken1Path);

        /* Rev share */
        uint256 _revShareAmount = _balUSDC.sub(_buybackAmount);
        // Determine appropriate swap path from USDC to ZOR depending on 
        // whether ZOR is the 0th or 1st token in the LP pair
        address[] memory USDCToZORPath;
        if (zorroLPPoolToken0 == ZORRO) {
            USDCToZORPath = USDCToZorroLPPoolToken0Path;
        } else {
            USDCToZORPath = USDCToZorroLPPoolToken1Path;
        }
        revShareOnChain(defaultStablecoin, USDCToZORPath, _revShareAmount);

        // Send cross chain burn request back to the remote chain
        XChainEndpoint endpointContract = XChainEndpoint(
            endpointContracts[_chainId]
        );
        bytes memory _payload = abi.encodeWithSignature(
            "receiveBurnLockedEarningsRequest(uint256 _amountUSDCBuyback,uint256 _amountUSDCRevShare,uint256 _failedAmountUSDCBuyback,uint256 _failedAmountUSDCRevShare)",
            _amountUSDCBuyback,
            _amountUSDCRevShare,
            _failedAmountUSDCBuyback,
            _failedAmountUSDCRevShare
        );
        endpointContract.sendXChainTransaction(
            _callbackContract,
            _payload,
            ""
        );
    }

    /// @notice Receives cross chain request for burning any temporarily locked funds for earnings
    /// @param _amountUSDCBuyback The amount in USDC that was bought back
    /// @param _amountUSDCRevShare The amount in USDC that was rev-shared
    /// @param _failedAmountUSDCBuyback The previously failed buyback amount that was successfully retried
    /// @param _failedAmountUSDCRevShare The previously failed revshare amount that was successfully retried
    function receiveBurnLockedEarningsRequest(
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare,
        uint256 _failedAmountUSDCBuyback, 
        uint256 _failedAmountUSDCRevShare
    ) external onlyXChainEndpoints {
        // Calculate total amount to unlock and burn
        uint256 _totalBurnableUSDC = _amountUSDCBuyback.add(_amountUSDCRevShare).add(_failedAmountUSDCBuyback).add(_failedAmountUSDCRevShare);
        // Unlock + burn
        TokenLockController(lockUSDCController).unlockFunds(
            address(this),
            _totalBurnableUSDC,
            burnAddress
        );
        // Decrement any failed amounts
        failedLockedBuybackUSDC = failedLockedBuybackUSDC.sub(_failedAmountUSDCBuyback);
        failedLockedRevShareUSDC = failedLockedRevShareUSDC.sub(_failedAmountUSDCRevShare);
    }

    /// @notice Recovery function for when home chain `receiveXChainDistributionRequest()` function fails
    /// @param _blockNumber The block number on the remote chain that the earnings distribution was for
    /// @param _pid The pool ID on the remote chain that the earnings distribution was from
    /// @param _amountBuybackUSDC The amount of buyback in USDC attempted for cross chain operations
    /// @param _amountRevShareUSDC The amount of revshare in USDC attempted for cross chain operations
    function recoverXChainFeeDist(
        uint256 _blockNumber,
        uint256 _pid,
        uint256 _amountBuybackUSDC,
        uint256 _amountRevShareUSDC
    ) external onlyXChainEndpoints {
        // Marks locked earnings as operation as failed.
        lockedEarningsStatus[_blockNumber][_pid] = 3;
        // Update accumulated total of failed earnings
        failedLockedBuybackUSDC = failedLockedBuybackUSDC.add(_amountBuybackUSDC);
        failedLockedRevShareUSDC = failedLockedRevShareUSDC.add(_amountRevShareUSDC);
    }

    /* Safety */
    /// @notice Called by oracle when the deposit logic on the remote chain failed, and the deposit logic on this chain thus needs to be reverted
    /// @dev Unlocks USDC and returns it to depositor
    /// @param _account The address of the depositor
    /// @param _netDepositUSDC The amount originally deposited, net of fees
    function revertXChainDeposit(address _account, uint256 _netDepositUSDC)
        public
        virtual
        onlyXChainEndpoints
    {
        // Unlock & return to wallet
        TokenLockController(lockUSDCController).unlockFunds(
            _account,
            _netDepositUSDC,
            _account
        );
    }
}
