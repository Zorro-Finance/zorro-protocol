// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ZorroControllerXChain.sol";

import "../../interfaces/LayerZero/ILayerZeroEndpoint.sol";

contract MockZorroControllerXChain is ZorroControllerXChain {
    event ReceiveXChainDepositReq(
        uint256 indexed _vid,
        uint256 indexed _valueUSD,
        address indexed _destAccount
    );

    event ReceiveXChainRepatriationReq(
        uint256 indexed _originChainId,
        uint256 indexed _rewardsDue
    );

    event ReceiveXChainDistributionReq(
        uint256 indexed _amountUSDBuyback,
        uint256 indexed _amountUSDRevShare,
        uint256 indexed _accSlashedRewards
    );

    event ReceiveXChainWithdrawalReq(
        uint256 indexed _originChainId,
        uint256 indexed _vid,
        uint256 indexed _trancheId
    );

    function mockReceiveXChainDepositRequest(
        uint256 _vid,
        uint256 _valueUSD,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        bytes memory _originAccount,
        address _destAccount
    ) public {
        _receiveXChainDepositRequest(
            _vid,
            _valueUSD,
            _weeksCommitted,
            block.timestamp,
            _maxMarketMovement,
            _originAccount,
            _destAccount
        );
    }

    function _receiveXChainDepositRequest(
        uint256 _vid,
        uint256 _valueUSD,
        uint256 _weeksCommitted,
        uint256 _vaultEnteredAt,
        uint256 _maxMarketMovement,
        bytes memory _originAccount,
        address _destAccount
    ) internal override {
        // Requirements
        require(_weeksCommitted >= 0);
        require(_vaultEnteredAt >= 0);
        require(_maxMarketMovement > 0);
        require(_originAccount.length >= 0);
        emit ReceiveXChainDepositReq(_vid, _valueUSD, _destAccount);
    }

    function mockReceiveXChainRepatriationRequest(
        uint256 _originChainId,
        uint256 _vid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _rewardsDue
    ) public {
        _receiveXChainRepatriationRequest(
            _originChainId,
            _vid,
            _trancheId,
            _originRecipient,
            _rewardsDue
        );
    }

    function _receiveXChainRepatriationRequest(
        uint256 _originChainId,
        uint256 _vid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _rewardsDue
    ) internal override {
        // Requirements
        require(_vid >= 0);
        require(_trancheId >= 0);
        require(_originRecipient.length >= 0);

        emit ReceiveXChainRepatriationReq(
            _originChainId,
            _rewardsDue
        );
    }

    function mockReceiveXChainDistributionRequest(
        uint256 _remoteChainId,
        uint256 _amountUSDBuyback,
        uint256 _amountUSDRevShare,
        uint256 _accSlashedRewards,
        uint256 _maxMarketMovement
    ) public {
        _receiveXChainDistributionRequest(
            _remoteChainId,
            _amountUSDBuyback,
            _amountUSDRevShare,
            _accSlashedRewards,
            _maxMarketMovement
        );
    }

    function _receiveXChainDistributionRequest(
        uint256 _remoteChainId,
        uint256 _amountUSDBuyback,
        uint256 _amountUSDRevShare,
        uint256 _accSlashedRewards,
        uint256 _maxMarketMovement
    ) internal override {
        // Requirements
        require(_remoteChainId >= 0);
        require(_maxMarketMovement > 0);

        emit ReceiveXChainDistributionReq(
            _amountUSDBuyback,
            _amountUSDRevShare,
            _accSlashedRewards
        );
    }

    function mockReceiveXChainWithdrawalRequest(
        uint256 _originChainId,
        bytes memory _originAccount,
        uint256 _vid,
        uint256 _trancheId,
        uint256 _maxMarketMovement
    ) public {
        _receiveXChainWithdrawalRequest(
            _originChainId,
            _originAccount,
            _vid,
            _trancheId,
            _maxMarketMovement
        );
    }

    function _receiveXChainWithdrawalRequest(
        uint256 _originChainId,
        bytes memory _originAccount,
        uint256 _vid,
        uint256 _trancheId,
        uint256 _maxMarketMovement
    ) internal override {
        // Requirements
        require(_originAccount.length >= 0);
        require(_maxMarketMovement > 0);

        emit ReceiveXChainWithdrawalReq(_originChainId, _vid, _trancheId);
    }

    function sendXChainRepatriationRequest(
        uint256 _originChainId,
        uint256 _vid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _amountUSD,
        uint256 _rewardsDue,
        uint256 _maxMarketMovementAllowed
    ) public payable {
        _sendXChainRepatriationRequest(
            _originChainId,
            _vid,
            _trancheId,
            _originRecipient,
            _amountUSD,
            _rewardsDue,
            _maxMarketMovementAllowed
        );
    }

    function awardSlashedRewardsToStakers(uint256 _slashedZORRewards)
        public
    {
        _awardSlashedRewardsToStakers(_slashedZORRewards);
    }
}

contract MockLayerZeroEndpoint is ILayerZeroEndpoint {
    event SentMessage(uint16 indexed _dstChainId, uint256 indexed msgValue);

    uint256 private _dummy; // For compiler satisfaction of state mutability

    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable {
        // Requirements
        require(_destination.length >= 0);
        require(_payload.length >= 0);
        require(_refundAddress != address(0));
        require(_zroPaymentAddress != address(0));
        require(_adapterParams.length >= 0);

        emit SentMessage(_dstChainId, msg.value);
    }

    function receivePayload(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        address _dstAddress,
        uint64 _nonce,
        uint256 _gasLimit,
        bytes calldata _payload
    ) external {}

    function getInboundNonce(uint16 _srcChainId, bytes calldata _srcAddress)
        external
        view
        returns (uint64)
    {}

    function getOutboundNonce(uint16 _dstChainId, address _srcAddress)
        external
        view
        returns (uint64)
    {}

    function estimateFees(
        uint16 _dstChainId,
        address _userApplication,
        bytes calldata _payload,
        bool _payInZRO,
        bytes calldata _adapterParam
    ) external view returns (uint256 nativeFee, uint256 zroFee) {
        // Requirements (to satisfy compiler warnings for unused variables)
        require(_dstChainId >= 0);
        require(_userApplication != address(0));
        require(_payload.length >= 0);
        require(_payInZRO || !_payInZRO); 
        require(_adapterParam.length >= 0);
        require(_dummy >= 0);

        return (0.1 ether, 0);
    }

    function getChainId() external view returns (uint16) {}

    function retryPayload(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        bytes calldata _payload
    ) external {}

    function hasStoredPayload(uint16 _srcChainId, bytes calldata _srcAddress)
        external
        view
        returns (bool)
    {}

    function getSendLibraryAddress(address _userApplication)
        external
        view
        returns (address)
    {}

    function getReceiveLibraryAddress(address _userApplication)
        external
        view
        returns (address)
    {}

    function isSendingPayload() external view returns (bool) {}

    function isReceivingPayload() external view returns (bool) {}

    function getConfig(
        uint16 _version,
        uint16 _chainId,
        address _userApplication,
        uint256 _configType
    ) external view returns (bytes memory) {}

    function getSendVersion(address _userApplication)
        external
        view
        returns (uint16)
    {}

    function getReceiveVersion(address _userApplication)
        external
        view
        returns (uint16)
    {}

    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint256 _configType,
        bytes calldata _config
    ) external {}

    function setSendVersion(uint16 _version) external {}

    function setReceiveVersion(uint16 _version) external {}

    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress)
        external
    {}
}
