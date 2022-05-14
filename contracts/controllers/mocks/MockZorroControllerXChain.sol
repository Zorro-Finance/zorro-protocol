// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ZorroControllerXChain.sol";

contract MockZorroControllerXChain is ZorroControllerXChain {
    event ReceiveXChainDepositReq(
        uint256 indexed _pid,
        uint256 indexed _valueUSDC,
        address indexed _destAccount
    );

    event ReceiveXChainRepatriationReq(
        uint256 indexed _originChainId,
        uint256 indexed _burnableZORRewards,
        uint256 indexed _rewardsDue
    );

    event ReceiveXChainDistributionReq(
        uint256 indexed _amountUSDCBuyback,
        uint256 indexed _amountUSDCRevShare,
        uint256 indexed _accSlashedRewards
    );

    event ReceiveXChainWithdrawalReq(
        uint256 indexed _originChainId,
        uint256 indexed _pid,
        uint256 indexed _trancheId
    );

    function encodeXChainDepositPayload(
        uint256 _chainId,
        uint256 _pid,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        address _originWallet,
        bytes memory _destWallet
    ) public view returns (bytes memory) {
        return
            _encodeXChainDepositPayload(
                _chainId,
                _pid,
                _valueUSDC,
                _weeksCommitted,
                _maxMarketMovement,
                _originWallet,
                _destWallet
            );
    }

    function mockReceiveXChainDepositRequest(
        uint256 _pid,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        bytes memory _originAccount,
        address _destAccount
    ) public {
        _receiveXChainDepositRequest(
            _pid,
            _valueUSDC,
            _weeksCommitted,
            block.timestamp,
            _maxMarketMovement,
            _originAccount,
            _destAccount
        );
    }

    function _receiveXChainDepositRequest(
        uint256 _pid,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _vaultEnteredAt,
        uint256 _maxMarketMovement,
        bytes memory _originAccount,
        address _destAccount
    ) internal override {
        // TODO: Consider making this an actual event like for repatriation, instead of one just for test
        emit ReceiveXChainDepositReq(_pid, _valueUSDC, _destAccount);
    }

    function mockReceiveXChainRepatriationRequest(
        uint256 _originChainId,
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _burnableZORRewards,
        uint256 _rewardsDue
    ) public {
        _receiveXChainRepatriationRequest(
            _originChainId,
            _pid,
            _trancheId,
            _originRecipient,
            _burnableZORRewards,
            _rewardsDue
        );
    }

    function _receiveXChainRepatriationRequest(
        uint256 _originChainId,
        uint256 _pid,
        uint256 _trancheId,
        bytes memory _originRecipient,
        uint256 _burnableZORRewards,
        uint256 _rewardsDue
    ) internal override {
        emit ReceiveXChainRepatriationReq(
            _originChainId,
            _burnableZORRewards,
            _rewardsDue
        );
    }

    function mockReceiveXChainDistributionRequest(
        uint256 _remoteChainId,
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare,
        uint256 _accSlashedRewards,
        uint256 _maxMarketMovement
    ) public {
        _receiveXChainDistributionRequest(
            _remoteChainId,
            _amountUSDCBuyback,
            _amountUSDCRevShare,
            _accSlashedRewards,
            _maxMarketMovement
        );
    }

    function _receiveXChainDistributionRequest(
        uint256 _remoteChainId,
        uint256 _amountUSDCBuyback,
        uint256 _amountUSDCRevShare,
        uint256 _accSlashedRewards,
        uint256 _maxMarketMovement
    ) internal override {
        emit ReceiveXChainDistributionReq(
            _amountUSDCBuyback,
            _amountUSDCRevShare,
            _accSlashedRewards
        );
    }

    function mockReceiveXChainWithdrawalRequest(
        uint256 _originChainId,
        bytes memory _originAccount,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement
    ) public {
        _receiveXChainWithdrawalRequest(
            _originChainId,
            _originAccount,
            _pid,
            _trancheId,
            _maxMarketMovement
        );
    }

    function _receiveXChainWithdrawalRequest(
        uint256 _originChainId,
        bytes memory _originAccount,
        uint256 _pid,
        uint256 _trancheId,
        uint256 _maxMarketMovement
    ) internal override {
        emit ReceiveXChainWithdrawalReq(_originChainId, _pid, _trancheId);
    }
}
