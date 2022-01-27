// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./helpers/ReentrancyGuard.sol";

import "./helpers/Pausable.sol";

import "./helpers/Ownable.sol";

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

/// @title XChainBaseLayer. Base contract for cross-chain functionality
contract XChainBaseLayer is Ownable, ReentrancyGuard, Pausable {
    /* Modifiers */
    /// @notice Only allows functions to be executed where the sender matches the authorizedOracle address
    modifier onlyAuthorizedOracle() {
        require(
            _msgSender() == authorizedOracle,
            "Only authd oracle can make call"
        );
        _;
    }
    /// @notice Only allows functions to be executed where the sender matches the authorizedRelayer address
    modifier onlyAuthorizedRelayer() {
        require(
            _msgSender() == authorizedRelayer,
            "Only authd relayer can make call"
        );
        _;
    }

    /* Events */
    event SentCrossChainBlockToOracle(uint256 indexed originChainBlockNumber);
    event OracleReceivedCrossChainBlock(uint256 indexed originChainBlockNumber);
    event RelayerReceivedCrossChainTx(bytes indexed transactionId);

    /* State */
    // TODO: Need to differentiate between Chainlink oracle and the account on the cloud function. Extra modifiers are needed
    address authorizedOracle;
    address authorizedRelayer;
    address oracleContract; // TODO setter, constructor
    address relayerContract; // TODO setter, constructor
    bytes32 notifyOracleJobId; // TODO setter, constructor
    bytes32 sendTxToRelayerJobId; // TODO setter, constructor
    bytes32 requestProofJobId; // TODO setter, constructor
    uint256 oraclePayment; // TODO setter

    /* Setters */
    /// @notice Sets the `authorizedOracle` address to a new address. This is designed to allow only a certain address to make calls
    /// @param _authorizedOracle The new address to authorize as the oracle
    function setAuthorizedOracle(address _authorizedOracle) public onlyOwner {
        authorizedOracle = _authorizedOracle;
    }

    /// @notice Sets the `authorizedRelayer` address to a new address. This is designed to allow only a certain address to make calls
    /// @param _authorizedRelayer The new address to authorize as the oracle
    function setAuthorizedRelayer(address _authorizedRelayer) public onlyOwner {
        authorizedRelayer = _authorizedRelayer;
    }
}

// TODO: How is a cross chain vault even defined? Where will logic for encoding the payload and function go? (Chain ID, contract address, function signature)
// TODO: How do we handle non EVM cross chain tx encoding? -> Serialize to bytes (whatever dest. chain's ABI equivalent is)
// TODO: Where do we decide on minting/burning etc.?
// TODO: Should we lock before burning?
// TODO: Consider emitting events to make debugging easier
// TODO: *** How do we keep chain of custody of msg.sender all the way across chains? -> Encode this in proveth.py, dest. contract needs to call the appropriate investment function and put in the replacement value for msg.sender
// TODO: *** How do we know that the payload hasn't been tampered with? Merkle proof? -> Check the `input` field

/// @title XChainEndpoint. The full contract (inherits from all contracts above) that interfaces with all cross-chain interactions
contract XChainEndpoint is XChainBaseLayer, ChainlinkClient {
    using Chainlink for Chainlink.Request;

    /* Constructor */
    /// @notice Constructor. Sets permissions
    /// @param _owner Address of intended owner for this contract
    /// @param _authorizedOracle Address of the only Oracle node allowed to make calls to this contract
    /// @param _authorizedRelayer Address of the only Relayer node allowed to make calls to this contract
    constructor(
        address _owner,
        address _authorizedOracle,
        address _authorizedRelayer
    ) {
        transferOwnership(_owner);
        authorizedOracle = _authorizedOracle;
        authorizedRelayer = _authorizedRelayer;
    }

    /*
    /// Contract Layer. Functions for interacting with other smart contracts for cross-chain purposes
    */

    /* Sending chain */
    /// @notice Starts off cross chain transaction by accepting contract & payload, and sending to Relay/Oracle layers
    /// @param _destinationContract Address of the destination contract to call (in bytes to keep generic)
    /// @param _payload Payload in ABI encoded bytes (or equivalent depending on chain)
    function sendXChainTransaction(
        bytes calldata _destinationContract,
        bytes calldata _payload
    ) public onlyOwner {
        // Call relay
        sendTransactionPacketToRelayer(_destinationContract, _payload);
        // Call oracle
        notifyOracle();
    }

    /* Receiving chain */
    /// @notice receives a validated transaction from the Relay layer and calls the on-chain destination contract to make a transaction
    /// @param _destinationContract Address of the destination contract to call to complete the cross chain transaction (in bytes to keep generic)
    /// @param _payload Payload in ABI encoded bytes (or equivalent depending on chain)
    function receiveXChainTransaction(
        address _destinationContract,
        bytes calldata _payload
    ) internal {
        // Perform contract call with the abi encoded payload
        (bool success, ) = _destinationContract.call(_payload);
        // Reverts if transaction does not succeed
        require(success, "Call to destination contract failed");
    }

    /*
    /// Relay Layer. Functions for interacting with the off-chain relayer.
    */

    /* Sending chain */
    /// @notice Sends transaction information to the Relayer
    /// @param _destinationContract universal address of the destination contract (in bytes to keep generic)
    /// @param _payload ABI-encoded payload (or equivalent). Encodes both the function call and the payload
    function sendTransactionPacketToRelayer(
        bytes calldata _destinationContract,
        bytes calldata _payload
    ) internal {
        // Create a Chainlink Request to send transaction info to the Relayer
        Chainlink.Request memory req = buildChainlinkRequest(
            sendTxToRelayerJobId,
            address(this),
            this.sendTransactionPacketToRelayerCallback.selector
        );
        req.addBytes("destContract", _destinationContract);
        req.addBytes("payload", _payload);
        sendChainlinkRequestTo(relayerContract, req, oraclePayment);
    }

    /// @notice Receives callback from Relayer, acknowledging receipt of transaction info
    /// @param _transactionId Universal transaction ID (e.g. transaction hash) of the tx info that was successfully sent to the Relayer
    function sendTransactionPacketToRelayerCallback(
        bytes calldata _transactionId
    ) external onlyAuthorizedOracle {
        // Emits notification to acknowledge transaction processed by relayer
        emit RelayerReceivedCrossChainTx(_transactionId);
    }

    /* Receiving chain */
    /// @notice Allows Endpoint to query Relayer for any transactions (and their proofs) matching the block hash provided
    /// @dev Meant to only be called internally by the Oracle layer. Triggers an async callback (validateTransactionsCallback)
    /// @param _blockHeaderHash Bytes representing the block header hash for the block of interest
    function requestTxProofsForBlock(bytes calldata _blockHeaderHash) internal {
        // Create Chainlink Direct Request that queries Relayer w/ block header hash
        Chainlink.Request memory req = buildChainlinkRequest(
            requestProofJobId,
            address(this),
            this.validateTxProofsCallback.selector
        );
        req.addBytes("blockHash", _blockHeaderHash);
        sendChainlinkRequestTo(relayerContract, req, oraclePayment);
    }

    /// @notice Receives callback from Relayer in order to validate all cross chain transactions in a given block on the sending chain
    /// @param _destinationContracts Array of addresses of destination contracts (one per tx)
    /// @param _payloads Array of payloads for each transaction
    /// @param _proofs Array of proofs (one per tx)
    function validateTxProofsCallback(
        address[] calldata _destinationContracts,
        bytes[] calldata _payloads,
        bytes[] calldata _proofs
    ) external onlyAuthorizedRelayer {
        // TODO complete function
        // Iterate through length of _proofs
        // For each proof, check against block header hash for validity
        // For the first failure, revert the entire transaction
        // Otherwise, call the Contract layer with the payloads and destination contracts
        // TODO - where are we getting the block header hash from to compare proofs? Probably store a hash as private var?
    }

    /*
    /// Oracle Layer. Functions for interacting with the oracle.
    */

    /* Sending chain */
    /// @notice Notifies the Oracle that the current block contains Zorro cross chain transactions
    /// @dev Meant to be called internally by the Contract layer
    function notifyOracle() internal {
        // Create Chainlink Direct Request that notifies Oracle
        Chainlink.Request memory req = buildChainlinkRequest(
            notifyOracleJobId,
            address(this),
            this.notifyOracleCallback.selector
        );
        sendChainlinkRequestTo(oracleContract, req, oraclePayment);
    }

    /// @notice Callback function for notifyOracle. Receives callback from Chainlink node after oracle job is run
    /// @param _blockNumber The number of the block that was recorded by the Oracle in the notifyOracle() call
    function notifyOracleCallback(uint256 _blockNumber)
        external
        onlyAuthorizedOracle
    {
        // Emit log
        emit SentCrossChainBlockToOracle(_blockNumber);
    }

    /* Receiving chain */
    /// @notice Receives message from the Oracle to begin the cross chain transaction on the receiving chain
    /// @dev Can only be called by Oracle
    /// @param _blockNumber A number representing the block of interest from the sending chain
    /// @param _blockHeaderHash A string of the block header hash from the sending chain
    function receiveOracleNotification(
        uint256 _blockNumber,
        bytes calldata _blockHeaderHash
    ) external onlyAuthorizedOracle {
        // Call Relay layer with block header hash
        requestTxProofsForBlock(_blockHeaderHash);
        // Emit log
        emit OracleReceivedCrossChainBlock(_blockNumber);
    }
}
