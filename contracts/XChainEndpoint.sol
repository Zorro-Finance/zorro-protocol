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

    /* Events */
    event SentCrossChainBlockToOracle(uint256 indexed originChainBlockNumber);
    event OracleReceivedCrossChainBlock(uint256 indexed originChainBlockNumber);
    event RelayerReceivedCrossChainTx(bytes indexed transactionId);

    /* Constants */
    uint8 public constant BLOCK_HEADER_HASH_NOT_EXIST = 0;
    uint8 public constant BLOCK_HEADER_HASH_IN_PROGRESS = 1;
    uint8 public constant BLOCK_HEADER_HASH_PROCESSED = 2;

    /* State */
    address authorizedOracle; // Oracle node address
    address authorizedRelayer; // Relayer node address
    address authorizedOracleController; // Controller that acts on behalf of the Oracle
    address oracleContract; // Address of Chainlink oracle contract
    address relayerContract; // Address of Chainlink relayer contract
    bytes32 notifyOracleJobId; // Job ID for notifying oracle of cross-chain block
    bytes32 sendTxToRelayerJobId; // Job ID for notifying relayer of new cross-chain TXs
    bytes32 requestProofJobId; // Job ID for requesting TX proofs from relayer
    uint256 oraclePayment; // Amount of LINK to pay Chainlink node operator

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
    function setNotifyOracleJobId(address _notifyOracleJobId) public onlyOwner {
      notifyOracleJobId = _notifyOracleJobId;
    }

    /// @notice Sets the job ID for sending cross-chain related transactions to the relayer
    /// @param _sendTxToRelayerJobId Job ID for sending transactions to the relayer
    function setSendTxToRelayerJobId(address _sendTxToRelayerJobId) public onlyOwner {
      sendTxToRelayerJobId = _sendTxToRelayerJobId;
    }

    /// @notice Sets the job ID for requesting all proofs and tx data for a block hash
    /// @param _requestProofJobId Job ID for requesting proofs from the relayer
    function setRequestProofJobId(address _requestProofJobId) public onlyOwner {
      requestProofJobId = _requestProofJobId;
    }

    /// @notice Sets the amount of LINK to pay to a Chainlink node
    function setOraclePayment(uint256 _oraclePayment) public onlyOwner {
      oraclePayment = _oraclePayment;
    }
}

// TODO: Should we lock before burning? Where do we decide on minting/burning etc.?
// TODO: *** How do we keep chain of custody of msg.sender all the way across chains? -> Encode this in proveth.py, dest. contract needs to call the appropriate investment function and put in the replacement value for msg.sender

/// @title XChainEndpoint. The full contract (inherits from all contracts above) that interfaces with all cross-chain interactions
contract XChainEndpoint is XChainBaseLayer, ChainlinkClient, ProvethVerifier {
    using Chainlink for Chainlink.Request;

    /* Constructor */
    /// @notice Constructor. Sets permissions
    /// @param _owner Address of intended owner for this contract
    /// @param _authorizedAddresses Array of addresses of authorized oracle/relayer addresses: [authorizedOracle, authorizedOracleController, authorizedRelayer]
    /// @param _oracleContracts Array of addresses of contracts oracle/relayer: [oracleContract, relayerContract]
    /// @param _jobIds Array of job IDs for oracle/relayer: [notifyOracleJobId, sendTxToRelayerJobId, requestProofJobId]
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
    function sendXChainTransaction(
        bytes calldata _destinationContract,
        bytes calldata _payload
    ) external onlyOwner {
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
}
