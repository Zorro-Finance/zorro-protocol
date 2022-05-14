// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ZorroControllerXChain.sol";

contract MockZorroControllerXChain is ZorroControllerXChain {
    event ReceiveXChainDepositReq(
        uint256 indexed _pid,
        uint256 indexed _valueUSDC,
        address indexed _destAccount
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
        _receiveXChainDepositRequest(_pid, _valueUSDC, _weeksCommitted, block.timestamp, _maxMarketMovement, _originAccount, _destAccount);
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
        emit ReceiveXChainDepositReq(_pid, _valueUSDC, _destAccount);
    }
}
