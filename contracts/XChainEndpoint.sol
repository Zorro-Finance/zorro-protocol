// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./helpers/ReentrancyGuard.sol";

import "./helpers/Pausable.sol";

import "./helpers/Ownable.sol";

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

import "./helpers/ProvethVerifier.sol";

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
    /// @notice Only allows functions to be executed where the sender matches the authorizedOracleController address
    modifier onlyAuthorizedOracleController() {
        require(
            _msgSender() == authorizedOracleController,
            "Only authd oracle ctrlr can make call"
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
    /// @notice Only allows functions to be executed where the sender is in contractLayerAuthorizedCallers
    modifier onlyAuthorizedCaller() {
        require(
            contractLayerAuthorizedCallers(_msgSender()) > 0,
            "Only authd contract caller allowed"
        );
        _;
    }

    /* Events */
    event SentCrossChainBlockToOracle(uint256 indexed originChainBlockNumber);
    event OracleReceivedCrossChainBlock(uint256 indexed originChainBlockNumber);
    event RelayerReceivedCrossChainTx(bytes indexed transactionId);

    /* Constants */
    uint8 public constant BLOCK_HEADER_HASH_NOT_EXIST = 0;
    uint8 public constant BLOCK_HEADER_HASH_IN_PROGRESS = 1;
    uint8 public constant BLOCK_HEADER_HASH_PROCESSED = 2;
    uint8 public constant BLOCK_HEADER_HASH_FAILED = 3;
    uint8 public constant BLOCK_HEADER_HASH_PROCESSING_FAILURE = 4;
    uint8 public constant BLOCK_HEADER_HASH_PROCESSED_FAILURE = 5;

    /* State */
    address public authorizedOracle; // Oracle node address
    address public authorizedRelayer; // Relayer node address
    address public authorizedOracleController; // Controller that acts on behalf of the Oracle
    address public oracleContract; // Address of Chainlink oracle contract
    address public relayerContract; // Address of Chainlink relayer contract
    bytes32 public notifyOracleJobId; // Job ID for notifying oracle of cross-chain block
    bytes32 public sendTxToRelayerJobId; // Job ID for notifying relayer of new cross-chain TXs
    bytes32 public requestProofJobId; // Job ID for requesting TX proofs from relayer
    bytes32 public checkFailureJobId; // Job ID for verifying TX failure
    bytes32 public fetchFailedTransactionsJobId; // Job ID for fetching all failed transactions on the origin chain
    uint256 public oraclePayment; // Amount of LINK to pay Chainlink node operator

    mapping(address => uint8) public contractLayerAuthorizedCallers; // Mapping of allowed cross chain transaction callers. Mapping: address => 0 or 1. 1 means allowed.
    mapping(bytes32 => uint8) private _blockHeaderHashes; // Stores block header hashes sent from Oracle. Mapping: hash => BLOCK_HEADER_HASH_* (see constants section)

    /* Setters */
    /// @notice Sets the `authorizedOracle` address to a new address. This is designed to allow only a certain address to make calls
    /// @param _authorizedOracle The new address to authorize as the oracle
    function setAuthorizedOracle(address _authorizedOracle) public onlyOwner {
        authorizedOracle = _authorizedOracle;
    }

    /// @notice Sets the `authorizedOracleController` address to a new address. This is designed to allow only a certain address to make calls
    /// @param _authorizedOracleController The new address to authorize as the oracle
    function setAuthorizedOracleController(address _authorizedOracleController) public onlyOwner {
        authorizedOracleController = _authorizedOracleController;
    }

    /// @notice Sets the `authorizedRelayer` address to a new address. This is designed to allow only a certain address to make calls
    /// @param _authorizedRelayer The new address to authorize as the oracle
    function setAuthorizedRelayer(address _authorizedRelayer) public onlyOwner {
        authorizedRelayer = _authorizedRelayer;
    }

    /// @notice Sets the oracle contract that Chainlink calls should be made to
    /// @param _oracleContract The oracle contract that the Chainlink node owns
    function setOracleContract(address _oracleContract) public onlyOwner {
      oracleContract = _oracleContract;
    }

    /// @notice Sets the relayer contract that Chainlink calls should be made to
    /// @param _relayerContract The oracle contract that the Chainlink node owns
    function setOracleContract(address _oracleContract) public onlyOwner {
      oracleContract = _oracleContract;
    }

    /// @notice Sets the job ID for notifying the oracle of a block with cross chain activity
    /// @param _notifyOracleJobId Job ID for notifying the oracle
    function setNotifyOracleJobId(bytes32 _notifyOracleJobId) public onlyOwner {
      notifyOracleJobId = _notifyOracleJobId;
    }

    /// @notice Sets the job ID for sending cross-chain related transactions to the relayer
    /// @param _sendTxToRelayerJobId Job ID for sending transactions to the relayer
    function setSendTxToRelayerJobId(bytes32 _sendTxToRelayerJobId) public onlyOwner {
      sendTxToRelayerJobId = _sendTxToRelayerJobId;
    }

    /// @notice Sets the job ID for requesting all proofs and tx data for a block hash
    /// @param _requestProofJobId Job ID for requesting proofs from the relayer
    function setRequestProofJobId(bytes32 _requestProofJobId) public onlyOwner {
      requestProofJobId = _requestProofJobId;
    }

    /// @notice Sets the job ID for requesting true failure state of a remote transaction
    /// @param _checkFailureJobId Job ID for checking failure state of a transaction on the relayer
    function setCheckFailureJobId(bytes32 _checkFailureJobId) public onlyOwner {
      checkFailureJobId = _checkFailureJobId;
    }

    /// @notice Sets the job ID for requesting all proofs and tx data for a block hash on the origin chain (for failed TXs)
    /// @param _checkFailureJobId Job ID for checking failure state of a transaction on the relayer
    function setFetchFailedTransactionsJobId(bytes32 _fetchFailedTransactionsJobId) public onlyOwner {
      fetchFailedTransactionsJobId = _fetchFailedTransactionsJobId;
    }

    /// @notice Sets the amount of LINK to pay to a Chainlink node
    function setOraclePayment(uint256 _oraclePayment) public onlyOwner {
      oraclePayment = _oraclePayment;
    }
}

/// @title XChainEndpoint. The full contract (inherits from all contracts above) that interfaces with all cross-chain interactions
contract XChainEndpoint is XChainBaseLayer, ChainlinkClient, ProvethVerifier {
    using Chainlink for Chainlink.Request;

    /* Constructor */
    /// @notice Constructor. Sets permissions
    /// @param _owner Address of intended owner for this contract
    /// @param _authorizedAddresses Array of addresses of authorized oracle/relayer addresses: [authorizedOracle, authorizedOracleController, authorizedRelayer]
    /// @param _oracleContracts Array of addresses of contracts oracle/relayer: [oracleContract, relayerContract]
    /// @param _jobIds Array of job IDs for oracle/relayer: [notifyOracleJobId, sendTxToRelayerJobId, requestProofJobId, checkFailureJobId, fetchFailedTransactionsJobId]
    /// @param _oraclePayment Amount of LINK to pay the node operator
    constructor(
        address _owner,
        address[] _authorizedAddresses,
        address[] _oracleContracts,
        bytes32[] _jobIds,
        uint256 _oraclePayment
    ) {
        // Set owner of this contract
        transferOwnership(_owner);
        // Set authorized resources
        authorizedOracle = _authorizedAddresses[0];
        authorizedOracleController = _authorizedAddresses[1];
        authorizedRelayer = _authorizedAddresses[2];
        // Set oracle contracts
        oracleContract = _oracleContracts[0];
        relayerContract = _oracleContracts[1];
        // Set job IDs
        notifyOracleJobId = _jobIds[0];
        sendTxToRelayerJobId = _jobIds[1];
        requestProofJobId = _jobIds[2];
        checkFailureJobId = _jobIds[3];
        fetchFailedTransactionsJobId = _jobIds[4];
        // Set node payment
        oraclePayment = _oraclePayment;
    }

    /*
    /// Contract Layer. Functions for interacting with other smart contracts for cross-chain purposes
    */

    /* Sending chain */
    /// @notice Starts off cross chain transaction by accepting contract & payload, and sending to Relay/Oracle layers
    /// @param _destinationContract Address of the destination contract to call (in bytes to keep generic)
    /// @param _payload Payload in ABI encoded bytes (or equivalent depending on chain)
    /// @param _recoveryPayload Same as above, except it is meant to be recovery instructions on this chain in the event of a failure on the remote chain (optional)
    function sendXChainTransaction(
        bytes calldata _destinationContract,
        bytes calldata _payload,
        bytes calldata _recoveryPayload
    ) external onlyAuthorizedCaller {
        // Call relay
        sendTransactionPacketToRelayer(_destinationContract, _payload, _recoveryPayload);
        // Call oracle
        notifyOracle();
    }

    /* Receiving chain */
    /// @notice receives a validated transaction from the Relay layer and calls the on-chain destination contract to make a transaction
    /// @param _destinationContract Address of the destination contract to call to complete the cross chain transaction (in bytes to keep generic)
    /// @param _payload Payload in ABI encoded bytes (or equivalent depending on chain)
    /// @param _revertPayload Same as above, except meant to be recovery instructions for sending chain in the event of failure (optional) (unused in this function, as it is meant for relayer to pick up)
    function receiveXChainTransaction(
        address _destinationContract,
        bytes calldata _payload
    ) internal {
        // Perform contract call with the abi encoded payload
        (bool success, ) = _destinationContract.call(_payload);
        // Reverts if transaction does not succeed
        require(success, "Call to receiving contract failed");
    }

    /*
    /// Relay Layer. Functions for interacting with the off-chain relayer.
    */

    /* Sending chain */
    /// @notice Sends transaction information to the Relayer
    /// @param _destinationContract universal address of the destination contract (in bytes to keep generic)
    /// @param _payload ABI-encoded payload (or equivalent). Encodes both the function call and the payload
    /// @param _recoveryPayload Same as above, except meant to be recovery instructions on this chain in the event of failure on remote chain (optional)
    function sendTransactionPacketToRelayer(
        bytes calldata _destinationContract,
        bytes calldata _payload,
        bytes calldata _recoveryPayload
    ) internal {
        // Create a Chainlink Request to send transaction info to the Relayer
        Chainlink.Request memory req = buildChainlinkRequest(
            sendTxToRelayerJobId,
            address(this),
            this.sendTransactionPacketToRelayerCallback.selector
        );
        req.addBytes("destContract", _destinationContract);
        req.addBytes("payload", _payload);
        req.addBytes("recoveryPayload", _recoveryPayload);
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
        // Update status
        _blockHeaderHashes[_blockHeaderHash] = BLOCK_HEADER_HASH_IN_PROGRESS;
    }

    /// @notice Receives callback from Relayer in order to validate all cross chain transactions in a given block on the sending chain
    /// @param _destinationContracts Array of addresses of destination contracts (one per tx)
    /// @param _payloads Array of payloads for each transaction
    /// @param _proofBlobs Array of proof blobs (one per tx)
    /// @param _blockHeaderHash The block header hash that was originally requested (will be checked against storage for authenticity)
    function validateTxProofsCallback(
        address[] calldata _destinationContracts,
        bytes[] calldata _payloads,
        bytes[] calldata _proofBlobs,
        bytes32 _blockHeaderHash
    ) external onlyAuthorizedRelayer {
        // Check that provided block hash was already sent by the oracle.
        require(
            _blockHeaderHashes[_blockHeaderHash] > BLOCK_HEADER_HASH_NOT_EXIST,
            "Block hash not recorded"
        );
        require(
            _blockHeaderHashes[_blockHeaderHash] ==
                BLOCK_HEADER_HASH_IN_PROGRESS,
            "Block hash not in progress"
        );
        // Iterate through length of _proofBlobs
        for (uint256 i = 0; i < _proofBlobs.length; i++) {
            // Get all values at current index
            bytes _destinationContract = _destinationContracts[i];
            bytes _payload = _payloads[i];
            // TODO - do we need to check if payload is in proof?
            bytes _proofBlob = _proofBlobs[i];
            // For each proof, check against block header hash for validity
            (uint8 res, , , , , , , , , , , ) = txProof(
                _blockHeaderHash,
                proofBlob
            );
            // If one proof is invalid, revert the entire transaction
            require(res == 1, "Failed to validate Tx Proof");
            // Call Contract Layer with payloads to finally execute the cross chain transaction
            receiveXChainTransaction(_destinationContract, _payload);
        }
        // Mark current hash as completed so that it does not run again
        _blockHeaderHashes[_blockHeaderHash] = BLOCK_HEADER_HASH_PROCESSED;
    }

    /// @notice Starts recovery process on this chain, assuming that the remote chain transaction failed
    /// @dev To be called only by Relayer
    /// @param _blockHashRemote The block header of the block on the origin chain in which the tx failed 
    /// @param _txHash The failed transaction hash on the remote chain
    function startRecovery(
        bytes calldata _blockHashOrigin,
        bytes calldata _txHash
    ) external onlyAuthorizedRelayer {
        // Asks Oracle if tx actually indeed fail
        // Create Chainlink Direct Request that queries Oracle w/ block header hash
        Chainlink.Request memory req = buildChainlinkRequest(
            checkFailureJobId,
            address(this),
            this.callbackRecovery.selector
        );
        req.addBytes("blockHash", _blockHashOrigin);
        req.addBytes("txHash", _txHash);
        sendChainlinkRequestTo(oracleContract, req, oraclePayment);
    }

    /// @notice Continues recovery process after receiving callback from Oracle to prove remote transaction failed
    /// @param _transactionDidFail True if the transaction did indeed fail 
    /// @param _blockHashOrigin The block header of the block on the origin chain associated with the cross chain transactions
    function callbackRecovery(
        bool _transactionDidFail,
        uint256 _blockHashOrigin
    ) external onlyAuthorizedOracle {
        // Revert if did not actually fail
        require(_transactionDidFail, "TX didnt fail");
        // Sends Relayer the block hash and asks for all matching Zorro origin transactions in that block
        // Create Chainlink Direct Request that queries Relayer w/ block header hash
        Chainlink.Request memory req = buildChainlinkRequest(
            getFailedTransactionsJobId,
            address(this),
            this.validateFailedTxProofsCallback.selector
        );
        req.addBytes("blockHash", _blockHashOrigin);
        sendChainlinkRequestTo(relayerContract, req, oraclePayment);
        // Update status
        _blockHeaderHashes[_blockHashOrigin] = BLOCK_HEADER_HASH_PROCESSING_FAILURE;
    }

    /// @notice Executes final recovery process after receiving callback from Relayer and proofs are validated
    /// @param _recoveryPayload Array of recovery instructions for each transaction
    /// @param _proofBlobs Array of proof blobs (one per tx)
    /// @param _blockHeaderHash The block header hash that was originally requested (will be checked against storage for authenticity)
    function validateFailedTxProofsCallback(
        bytes[] calldata _recoveryPayloads,
        bytes[] calldata _proofBlobs,
        bytes32 _blockHeaderHash
    ) external onlyAuthorizedRelayer {
        // TODO
        // Check status
        require(
            _blockHeaderHashes[_blockHeaderHash] > BLOCK_HEADER_HASH_NOT_EXIST,
            "Block hash not recorded"
        );
        require(
            _blockHeaderHashes[_blockHeaderHash] == BLOCK_HEADER_HASH_PROCESSING_FAILURE,
            "Block hash not in progress"
        );

        // Iterate through all payloads/blobs
        for (uint256 i = 0; i < _proofBlobs.length; i++) {
            // Get all values at current index
            bytes _recoveryPayload = _recoveryPayloads[i];
            // TODO - do we need to check if payload is in proof?
            bytes _proofBlob = _proofBlobs[i];
            // For each proof, check against block header hash for validity
            (uint8 res, , , , , , , , , , , ) = txProof(
                _blockHeaderHash,
                _proofBlob
            );
            // If one proof is invalid, revert the entire transaction
            require(res == 1, "Failed to validate Tx Proof");
            // TODO: Extract msg.sender from each proof (the calling contract). Here is just a dummy variable but it should be 
            // a value from the tuple return value from txProof() above. 
            _originContract = address(0);
            // Call origin contract with the recovery payload
            receiveXChainTransaction(_originContract, _recoveryPayload);
        }
        // Mark current hash as completed so that it does not run again
        _blockHeaderHashes[_blockHeaderHash] = BLOCK_HEADER_HASH_PROCESSED_FAILURE;
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
    ) external onlyAuthorizedOracleController {
        // Call Relay layer with block header hash
        requestTxProofsForBlock(_blockHeaderHash);
        // Emit log
        emit OracleReceivedCrossChainBlock(_blockNumber);
    }

    /* Encoding/Decoding */

    /// @notice Takes an encoded bytes payload and extracts out the _account parameter. Can be overriden depending on unique chain requirements
    /// @dev The _account parameter MUST be the first input argument of the receiving function on the remote chain (address (20-bit) datatype)
    /// @param _payload The encoded (e.g. ABI encoded for EVM chains) function payload
    /// @return Extracted address
    function extractIdentityFromPayload(bytes _payload) public view virtual returns (address) {
        // TODO
        // Remove the first 4 bytes (Keccak 256 method signature)
        // Take the next 20 bits 
        // ABI decode to "address" datatype
        // Return address
    }

    /// @notice Takes an encoded bytes payload (usually intended for deposit/repatriation) and extracts out the _value parameter. Can be overriden depending on unique chain requirements
    /// @dev The _value parameter MUST be the second input argument of the receiving function on the remote chain (uint256 data type)
    /// @param _payload The encoded (e.g. ABI encoded for EVM chains) function payload
    /// @return Extracted address
    function extractValueFromPayload(bytes _payload) public view virtual returns (address) {
        // TODO
        // Remove the first 4 bytes (Keccak 256 method signature) + 20 bits (address)
        // Take the next 256 bits 
        // ABI decode to "uint256" datatype
        // Return address
    }

    /// @notice Takes a given account and amount and encodes an unlock request in bytes for EVM chains. Can be overriden for other chains
    /// @param _account The address of the wallet (cross chain identity) to unlock funds for
    /// @param _amountUSDC The amount in USDC that should be unlocked and burned
    /// @return The ABI econded bytes. For other chains, it will be those chains' standard serializations in bytes.
    function encodeUnlockRequest(address _account,uint256 _amountUSDC) public view virtual returns (bytes) {
        // Abi encode the payload and return it (override this for other chains, which use a different encoding)        
        return abi.encodeWithSignature(
            "receiveXChainUnlockRequest(address _account,uint256 _amountUSDC)", 
            _account, _amountUSDC
        );
    }
}
