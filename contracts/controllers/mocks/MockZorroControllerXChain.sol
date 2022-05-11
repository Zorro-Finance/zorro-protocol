// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ZorroControllerXChain.sol";

contract MockZorroControllerXChain is ZorroControllerXChain {
    function encodeXChainDepositPayload(
        uint256 _pid,
        uint256 _valueUSDC,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        address _originWallet,
        bytes memory _destWallet
    ) public pure returns (bytes memory) {
        return
            _encodeXChainDepositPayload(
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
}
