// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./helpers/ReentrancyGuard.sol";

import "./helpers/Pausable.sol";

import "./helpers/Ownable.sol";

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

    /* State */
    address authorizedOracle;
    address authorizedRelayer;

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

/// @title XChainContractLayer. Functions for interacting with other smart contracts for cross-chain purposes
contract XChainContractLayer is XChainBaseLayer {
    /* Sending chain */
    /// @notice Starts off cross chain transaction by accepting contract & payload, and sending to Relay/Oracle layers
    /// @param _destinationContract Address of the destination contract to call
    /// @param _payload Payload in ABI encoded bytes (or equivalent depending on chain)
    function sendXChainTransaction(
        address _destinationContract,
        bytes calldata _payload
    ) public onlyOwner {
        // TODO
    }

    /* Receiving chain */
    /// @notice receives a validated transaction from the Relay layer and calls the on-chain destination contract to make a transaction
    /// @param _destinationContract Address of the destination contract to call to complete the cross chain transaction
    /// @param _payload Payload in ABI encoded bytes (or equivalent depending on chain)
    function receiveXChainTransaction(
        address _destinationContract,
        bytes calldata _payload
    ) internal {
        // TODO
    }
}

/// @title XChainRelayLayer. Functions for interacting with the off-chain relayer.
contract XChainRelayLayer is XChainBaseLayer {
    /* Sending chain */
    /// @notice Sends transaction information to the Relayer
    /// @param _destinationContract universal address of the destination contract
    /// @param _payload ABI-encoded payload (or equivalent). Encodes both the function and the payload
    function sendTransactionPacketToRelayer(
        address _destinationContract,
        bytes calldata _payload
    ) internal {
        // TODO
        // TODO - destination contract address - Needs to be generalized enough for non EVM chains
        // TODO - payload - Can this be encoded/decoded in bytes on all chains? EVM and otherwise?
        // Consider having EVM and non-EVM versions to save gas
    }

    /* Receiving chain */
    /// @notice Allows Endpoint to query Relayer for any transactions (and their proofs) matching the block hash provided
    /// @dev Meant to only be called internally by the Oracle layer. Triggers an async callback (validateTransactionsCallback)
    /// @param _blockHeaderHash Bytes representing the block header hash for the block of interest
    function requestProofsForBlock(bytes calldata _blockHeaderHash) internal {
        // TODO
    }

    /// @notice Receives callback from Relayer in order to validate all cross chain transactions in a given block on the sending chain
    /// @param _destinationContracts Array of addresses of destination contracts (one per tx)
    /// @param _payloads Array of payloads for each transaction
    /// @param _proofs Array of proofs (one per tx)
    function validateTransactionsCallback(
        address[] calldata _destinationContracts,
        bytes[] calldata _payloads,
        bytes[] calldata _proofs
    ) external onlyAuthorizedRelayer {
        // TODO
    }
}

/// @title XChainOracleLayer. Functions for interacting with the oracle.
contract XChainOracleLayer is XChainBaseLayer {
    /* Sending chain */
    /// @notice Notifies the Oracle that the current block contains Zorro cross chain transactions
    /// @dev Meant to be called internally by the Contract layer
    function notifyOracle() internal {
        // TODO
        // TODO - block number - should it be generalized to a string for other chains?
    }

    /* Receiving chain */
    /// @notice Receives message from the Oracle to begin the cross chain transaction on the receiving chain
    /// @dev Can only be called by Oracle
    /// @param _blockNumber A number representing the block of interestn from the sending chain
    /// @param _blockHeaderHash A string of the block header hash from the sending chain
    function receiveOracleNotification(
        uint256 _blockNumber,
        bytes calldata _blockHeaderHash
    ) external onlyAuthorizedOracle {
        // TODO
        // TODO - block number - should it be generalized to a string for other chains?
    }
}

/// @title XChainEndpoint. The full contract (inherits from all contracts above) that interfaces with all cross-chain interactions
contract XChainEndpoint is
    XChainContractLayer,
    XChainRelayLayer,
    XChainOracleLayer
{
    /* Constructor */
    /// @notice Constructor. Sets permissions
    /// @param _owner Address of intended owner for this contract
    constructor(address _owner) {
        transferOwnership(_owner);
    }
}
