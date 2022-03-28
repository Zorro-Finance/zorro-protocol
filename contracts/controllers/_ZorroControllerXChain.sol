// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerInvestment.sol";

import "../tokens/TokenLockController.sol";

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

import "../interfaces/IAMMRouter02.sol";

import "../interfaces/IVault.sol";

import "../libraries/SafeSwap.sol";


contract ZorroControllerXChain is ZorroControllerInvestment, ChainlinkClient {
    /* Libraries */
    using Chainlink for Chainlink.Request;
    using SafeSwapUni for IAMMRouter02;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* Modifiers */
    /// @notice Ensures that the claimed x chain sender is actually a recognized oracle
    // TODO: Check to see if this was supposed to be tx.origin or msg.sender?
    modifier onlyAuthorizedXChainOracle(bytes memory _xChainSender) {
        require(keccak256(_xChainSender) == keccak256(abi.encodePacked(xChainReceivingOracle)), "Unrecog rcvg oracle");
        _;
    }


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
        /* TODO
        - Make logic below LayerZero compatible. Requirements:
        -- Rather than accept a raw payload, use the current msg.sender identity, amount, pid, etc. (all args required for fullServiceDeposit)
        -- ABI encode the request here instaed of relying on the payload to be submitted elsewhere.
        -- Collect the appropriate deposit fee here. May need a separate function that the UI calls to get a quote first!
        -- Call Stargate interface, send tokens

        // Get endpoint contract that interfaces with the remote chain
        XChainEndpoint _endpointContract = XChainEndpoint(
            endpointContracts[_chainId]
        );
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

        // TODO*: Need to collect a xchain deposit fee here! And the net amount of the deposit needs to be accounted for somehow.

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
        */
    }

    /*
    TODO - modification required for this func:
    - Need separate func to receive Stargate cross chain call
    - Need a ledger that gets updated with the received amount, and awaits further processing
    - Need a func that a Chainlink oracle can call and periodically trigger processing of outstanding deposits on the ledger
    - Deposits should reflect the identity of both the origin sender and (optionally) the destnation chain address 
    - Adjust modifiers accordingly
    */
    /// @notice Receives a cross chain deposit request from the contract layer of the XchainEndpoint contract
    /// @dev For params, see _depositFullService() function declaration above
    /// @param _xChainOrigin Address of the original sender (in bytes) on the remote chain (equiv to tx.origin). Injected by endpoint contract after verifying proof
    function receiveXChainDepositRequest(
        address _account,
        uint256 _valueUSDC,
        uint256 _pid,
        uint256 _weeksCommitted,
        uint256 _vaultEnteredAt,
        uint256 _maxMarketMovement,
        bytes memory _xChainOrigin,
        bytes memory _xChainSender
    ) external onlyXChainEndpoints onlyXChainZorroControllers(_xChainSender) {
        // TODO: Confirm that USDC value requested exists on the ledger for this user and hasn't been processed yet

        // Call deposit function
        // TODO: Func below needs a pricedata struct. May require a call to an Oracle
        // _depositFullService(
        //     _pid,
        //     _account,
        //     _valueUSDC,
        //     _weeksCommitted,
        //     _vaultEnteredAt,
        //     _maxMarketMovement
        // );

        // TODO: Show deposit has been transferred on the ledger (completed). Must be able to account for multiple deposits 
        // in succession for the same user identity.
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
        /* TODO
        - Rather than accept a raw payload, it should be a simple request for chainId, pid, trancheId. 100% withdrawal. ABI encoding can be done here
        - Use LayerZero interface to make cross chain request
        - Consider creating a separate func to query xchain fees (gas etc.) and send that amount in the "value" field

        // Get endpoint contract that interfaces with the remote chain
        XChainEndpoint _endpointContract = XChainEndpoint(
            endpointContracts[_chainId]
        );
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
        */
    }

    /*
    TODO - modification required for this func:
    - Need separate func to receive LayerZero cross chain call, should extract origin chain identity and use that for identifying the user's investment to withdraw
    - Adjust modifiers accordingly
    */
    /// @notice Receives a cross chain withdrawal request from the contract layer of the XchainEndpoint contract
    /// @dev For params, see _withdrawalFullService() function declaration above. Executes idempotently.
    /// @param _xChainOrigin Address of the original sender (in bytes) on the remote chain (equiv to tx.origin). Injected by endpoint contract after verifying proof
    function receiveXChainWithdrawalRequest(
        address _account,
        uint256 _chainId,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement,
        bytes memory _xChainOrigin,
        bytes memory _xChainSender
    ) external onlyXChainEndpoints onlyXChainZorroControllers(_xChainSender) {
        // First check if withdrawal was already attempted (e.g. there was a cross chain failure). If so, redrive this function
        // without the withdrawal and lock steps
        TrancheInfo memory tranche = trancheInfo[_pid][_account][_trancheId];
        uint256 _amountUSDC = 0;
        if (tranche.exitedVaultStartingAt == 0) {
            // Call withdrawal function
            // TODO: This requires a pricedata struct. Maybe make this an 
            // Oracle call instead?
            // _amountUSDC = _withdrawalFullService(
            //     _account,
            //     _pid,
            //     _trancheId,
            //     false,
            //     _maxMarketMovement
            // );
            // Lock withdrawn USDC
            TokenLockController(lockUSDCController).lockFunds(
                _account,
                _amountUSDC
            );
        } else {
            // Lookup amount locked
            // TODO: Does this ledger need to be associated with the exact tranche amount? 
            // This appears to simply lookup the total amount which may be missing information. 
            // Actually since this is for reverts, might want to adopt a similar "ledger" model for deposits
            // that accounts for failures on cross-chain transactions (esp. for repatriation flow).
            _amountUSDC = TokenLockController(lockUSDCController).lockedFunds(
                _account
            );
        }

        // Only proceed if there is something to withdraw
        require(_amountUSDC > 0, "Nothing to withdraw");

        /*
        TODO: Replace the following with a Stargate call. Should transfer 
        // Prepare repatriation transaction
        bytes memory _destinationContract = abi.encodePacked(
            homeChainZorroController
        );
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
        XChainEndpoint _xChainEndpoint = XChainEndpoint(
            endpointContracts[homeChainId]
        );
        _xChainEndpoint.sendXChainTransaction(
            _destinationContract,
            _payload,
            ""
        );
        */
    }

    /*
    TODO
    - Consider using a "ledger" model here, accompanied by a recovery function, to account for failures
    - Instead of minting zUSDC and swapping it, accept the USDC that has been transferred
    - Cross chain unlock request should be a LayerZero call
    */
    /// @notice Receives a repatriation request from another chain and takes care of all financial operations (unlock/mint/burn) to pay the user their withdrawn funds from another chain
    /// @param _account The user on this chain who initiated the withdrawal request
    /// @param _withdrawnUSDC The amount of USDC withdrawn on the remote chain
    /// @param _chainId The Chain ID of the remote chain that initiated this request
    /// @param _originalNetDepositUSDC The amount originally deposited into this tranche, NET of fees
    /// @param _maxMarketMovement factor to account for max market movement/slippage, expressed as numerator over 1000 (e.g. 950 => 950/1000 = 0.95 = 5% slippage)
    /// @param _callbackContract The remote contract that called this function.
    /// @param _xChainOrigin Address of the original sender (in bytes) on the remote chain (equiv to tx.origin). Injected by endpoint contract after verifying proof
    function receiveXChainRepatriationRequest(
        address _account,
        uint256 _withdrawnUSDC,
        uint256 _chainId,
        uint256 _originalNetDepositUSDC,
        uint256 _maxMarketMovement,
        address _callbackContract,
        bytes memory _xChainOrigin,
        bytes memory _xChainSender
    ) external onlyXChainEndpoints nonReentrant onlyXChainZorroControllers(_xChainSender) {
        /*
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
                1e12,
                1e12,
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
        _sendXChainUnlockRequest(
            _account,
            _withdrawnUSDC,
            _chainId,
            abi.encodePacked(_callbackContract)
        );
        */
    }

    /* Unlocks */

    // TODO: Make this a LayerZero call
    /// @notice Sends a request to the remote chain to unlock and burn temporarily withheld USDC. To be called after a successful withdrawal
    /// @dev Internal function, only to be called by receiveXChainRepatriationRequest()
    /// @param _account The address of the wallet (cross chain identity) to unlock funds for
    /// @param _amountUSDC The amount in USDC that should be unlocked and burned
    /// @param _chainId The Zorro destination chain ID so that the request can be routed to the appropriate chain
    /// @param _destinationContract The address of the contract on the remote chain to send the unlock request to
    function _sendXChainUnlockRequest(
        address _account,
        uint256 _amountUSDC,
        uint256 _chainId,
        bytes memory _destinationContract
    ) internal {
        // TODO: Replace entire call with a LayerZero request to the other chain. Q: How to deal with uncertain fee calculations?
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

    // TODO This should be called from a LayerZero receiver
    /// @notice Receives a request from home chain to unlock and burn temporarily withheld USDC.
    /// @param _account The address of the wallet (cross chain identity) to unlock funds for
    /// @param _amountUSDC The amount in USDC that should be unlocked and burned
    function receiveXChainUnlockRequest(
        address _account,
        uint256 _amountUSDC,
        bytes memory _xChainOrigin,
        bytes memory _xChainSender
    ) external onlyXChainEndpoints onlyXChainZorroControllers(_xChainSender) {
        // Get controller
        TokenLockController lockController = TokenLockController(
            lockUSDCController
        );
        // Unlock user funds & burn
        lockController.unlockFunds(_account, _amountUSDC, burnAddress);
    }

    /* Earnings/Distribution */

    /// @notice Prepares and sends an earnings distribution request cross-chain (back to the home chain)
    /// @param _pid The pool ID associated with the vault which experienced earnings
    /// @param _buybackAmountUSDC The amount of USDC to buyback
    /// @param _revShareAmountUSDC The amount of USDC to share as revenue to the ZOR staking vault
    function distributeEarningsXChain(
        uint256 _pid,
        uint256 _buybackAmountUSDC,
        uint256 _revShareAmountUSDC
    ) public onlyRegisteredVault(_pid) {
        /* 
        TODO Convert this to a LayerZero call

        // Check lock to see if anything is pending for this block and pool. If so, revert
        require(
            lockedEarningsStatus[block.number][_pid] == 0,
            "Xchain earnings lock pending"
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
        XChainEndpoint xChainEndpoint = XChainEndpoint(
            endpointContracts[homeChainId]
        );

        // Construct payload
        bytes memory _payload = abi.encodeWithSignature(
            "receiveXChainDistributionRequest(uint256 _chainId,bytes _callbackContract,uint256 _amountUSDCBuyback,uint256 _amountUSDCRevShare,uint256 _failedAmountUSDCBuyback,uint256 _failedAmountUSDCRevShare)",
            chainId,
            abi.encode(address(this)),
            _buybackAmountUSDC,
            _revShareAmountUSDC,
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
        */
    }

    /// @notice Receives an authorized request from remote chains to perform earnings fee distribution events, such as: buyback + LP + burn, and revenue share
    /// @param _chainId The ID of the chain that this request originated from
    /// @param _callbackContract Address of destination contract in bytes for the callback
    /// @param _amountUSDCBuyback The amount in USDC that should be minted for LP + burn
    /// @param _amountUSDCRevShare The amount in USDC that should be minted for revenue sharing with ZOR stakers
    /// @param _failedAmountUSDCBuyback The previously failed buyback amount that is being retried
    /// @param _failedAmountUSDCRevShare The previously failed revshare amount that is being retried
    /// @param _xChainOrigin Address of the original sender (in bytes) on the remote chain (equiv to tx.origin). Injected by endpoint contract after verifying proof
    function receiveXChainDistributionRequest(
        uint256 _chainId,
        bytes calldata _callbackContract,
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare,
        uint256 _failedAmountUSDCBuyback,
        uint256 _failedAmountUSDCRevShare,
        bytes memory _xChainOrigin,
        bytes memory _xChainSender
    ) external onlyXChainEndpoints onlyXChainZorroControllers(_xChainSender) {
        // Make Chainlink request to get ZOR price
        Chainlink.Request memory req = buildChainlinkRequest(
            zorroControllerOraclePriceJobId,
            address(this),
            this.buybackAndRevShareCallback.selector
        );
        req.addBytes("chainId", abi.encodePacked(_chainId));
        req.addBytes("callbackContract", abi.encodePacked(_callbackContract));
        req.addBytes("amountUSDCBuyback", abi.encodePacked(_amountUSDCBuyback));
        req.addBytes(
            "amountUSDCRevShare",
            abi.encodePacked(_amountUSDCRevShare)
        );
        req.addBytes(
            "failedAmountUSDCBuyback",
            abi.encodePacked(_failedAmountUSDCBuyback)
        );
        req.addBytes(
            "failedAmountUSDCRevShare",
            abi.encodePacked(_failedAmountUSDCRevShare)
        );
        sendChainlinkRequestTo(
            zorroControllerOracle,
            req,
            zorroControllerOracleFee
        );
    }

    /// @notice Receives cross chain request for burning any temporarily locked funds for earnings
    /// @param _amountUSDCBuyback The amount in USDC that was bought back
    /// @param _amountUSDCRevShare The amount in USDC that was rev-shared
    /// @param _failedAmountUSDCBuyback The previously failed buyback amount that was successfully retried
    /// @param _failedAmountUSDCRevShare The previously failed revshare amount that was successfully retried
    /// @param _xChainOrigin Address of the original sender (in bytes) on the remote chain (equiv to tx.origin). Injected by endpoint contract after verifying proof
    function receiveBurnLockedEarningsRequest(
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare,
        uint256 _failedAmountUSDCBuyback,
        uint256 _failedAmountUSDCRevShare,
        bytes memory _xChainOrigin,
        bytes memory _xChainSender
    ) external onlyXChainEndpoints onlyXChainZorroControllers(_xChainSender) {
        // Calculate total amount to unlock and burn
        uint256 _totalBurnableUSDC = _amountUSDCBuyback
            .add(_amountUSDCRevShare)
            .add(_failedAmountUSDCBuyback)
            .add(_failedAmountUSDCRevShare);
        // Unlock + burn
        TokenLockController(lockUSDCController).unlockFunds(
            address(this),
            _totalBurnableUSDC,
            burnAddress
        );
        // Decrement any failed amounts
        failedLockedBuybackUSDC = failedLockedBuybackUSDC.sub(
            _failedAmountUSDCBuyback
        );
        failedLockedRevShareUSDC = failedLockedRevShareUSDC.sub(
            _failedAmountUSDCRevShare
        );
    }

    // TODO: Ledger system in case this fails?
    /// @notice Receives an authorized request from remote chains to perform earnings fee distribution events, such as: buyback + LP + burn, and revenue share
    /// @dev Can only be called by the Chainlink Oracle
    /// @param _chainId The ID of the chain that this request originated from
    /// @param _callbackContract Address of destination contract in bytes for the callback
    /// @param _amountUSDCBuyback The amount in USDC that should be minted for LP + burn
    /// @param _amountUSDCRevShare The amount in USDC that should be minted for revenue sharing with ZOR stakers
    /// @param _failedAmountUSDCBuyback The previously failed buyback amount that is being retried
    /// @param _failedAmountUSDCRevShare The previously failed revshare amount that is being retried
    /// @param _ZORROExchangeRate ZOR per USD, times 1e12
    function buybackAndRevShareCallback(
        uint256 _chainId,
        bytes calldata _callbackContract,
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare,
        uint256 _failedAmountUSDCBuyback,
        uint256 _failedAmountUSDCRevShare,
        uint256 _ZORROExchangeRate
    ) external onlyAllowZorroControllerOracle {
        // Total USDC to perform operations
        // TODO: How do failed amounts come into play here?
        uint256 _amountUSDC = _amountUSDCBuyback
            .add(_amountUSDCRevShare)
            .add(_failedAmountUSDCBuyback)
            .add(_failedAmountUSDCRevShare);

        // Determine new USDC balances
        uint256 _balUSDC = IERC20(defaultStablecoin).balanceOf(address(this));

        /* Buyback */
        uint256 _buybackAmount = _balUSDC
            .mul(_amountUSDCBuyback.add(_failedAmountUSDCBuyback))
            .div(_amountUSDC);
        _buybackOnChain(_buybackAmount, _ZORROExchangeRate);

        /* Rev share */
        uint256 _revShareAmount = _balUSDC.sub(_buybackAmount);
        _revShareOnChain(_revShareAmount, _ZORROExchangeRate);

        // Send cross chain burn request back to the remote chain
        /* 
        TODO: Convert to LayerZero call

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
        endpointContract.sendXChainTransaction(_callbackContract, _payload, "");
        */
    }

    /* Reverts */

    /// @notice Recovery function for when home chain `receiveXChainDistributionRequest()` function fails
    /// @param _blockNumber The block number on the remote chain that the earnings distribution was for
    /// @param _pid The pool ID on the remote chain that the earnings distribution was from
    /// @param _amountBuybackUSDC The amount of buyback in USDC attempted for cross chain operations
    /// @param _amountRevShareUSDC The amount of revshare in USDC attempted for cross chain operations
    /// @param _xChainOrigin Address of the original sender (in bytes) on the remote chain (equiv to tx.origin). Injected by endpoint contract after verifying proof
    function recoverXChainFeeDist(
        uint256 _blockNumber,
        uint256 _pid,
        uint256 _amountBuybackUSDC,
        uint256 _amountRevShareUSDC,
        bytes memory _xChainOrigin,
        bytes memory _xChainSender
    ) external onlyXChainEndpoints onlyAuthorizedXChainOracle(_xChainOrigin) {
        // Marks locked earnings as operation as failed.
        lockedEarningsStatus[_blockNumber][_pid] = 3;
        // Update accumulated total of failed earnings
        failedLockedBuybackUSDC = failedLockedBuybackUSDC.add(
            _amountBuybackUSDC
        );
        failedLockedRevShareUSDC = failedLockedRevShareUSDC.add(
            _amountRevShareUSDC
        );
    }

    /// @notice Called by oracle when the deposit logic on the remote chain failed, and the deposit logic on this chain thus needs to be reverted
    /// @dev Unlocks USDC and returns it to depositor
    /// @param _account The address of the depositor
    /// @param _netDepositUSDC The amount originally deposited, net of fees
    /// @param _xChainOrigin Address of the original sender (in bytes) on the remote chain (equiv to tx.origin). Injected by endpoint contract after verifying proof
    function revertXChainDeposit(
        address _account,
        uint256 _netDepositUSDC,
        bytes memory _xChainOrigin,
        bytes memory _xChainSender
    ) public virtual onlyXChainEndpoints onlyAuthorizedXChainOracle(_xChainOrigin) {
        // Unlock & return to wallet
        TokenLockController(lockUSDCController).unlockFunds(
            _account,
            _netDepositUSDC,
            _account
        );
    }
}