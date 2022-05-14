// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/ILayerZeroReceiver.sol";

import "../interfaces/IStargateReceiver.sol";

import "./_ZorroControllerXChainDeposit.sol";

import "./_ZorroControllerXChainWithdraw.sol";

import "./_ZorroControllerXChainEarn.sol";

import "../interfaces/IZorroControllerXChain.sol";

contract ZorroControllerXChainReceiver is
    IZorroControllerXChainReceiver,
    ZorroControllerXChainDeposit,
    ZorroControllerXChainWithdraw,
    ZorroControllerXChainEarn
{
    /* Modifiers */
    /// @notice Ensures cross chain request is coming from a recognized controller
    /// @param _lzChainId Layer Zero chain ID
    /// @param _callingContract The cross chain sender (should be a Zorro controller)
    modifier onlyRegXChainController(
        uint16 _lzChainId,
        bytes memory _callingContract
    ) {
        uint256 _zChainId = LZChainToZorroMap[_lzChainId];
        require(
            keccak256(controllerContractsMap[_zChainId]) ==
                keccak256(_callingContract),
            "Unrecog xchain controller"
        );
        _;
    }

    /* Receivers */

    /// @notice Receives stargate cross-chain calls
    /// @dev Implements IStargateReceiver interface
    function sgReceive(
        uint16 _chainId,
        bytes memory _srcAddress,
        uint256 _nonce,
        address _token,
        uint256 amountLD,
        bytes memory payload
    ) public override onlyRegXChainController(_chainId, _srcAddress) {
        // Checks / authorization
        // Amounts
        uint256 _tokenBal = IERC20(_token).balanceOf(address(this));
        require(amountLD <= _tokenBal, "amountLD exceeds bal");

        // Determine function based on signature
        // Get func signature
        bytes4 _funcSig = bytes4(payload);
        // Get params payload only
        bytes memory _paramsPayload = this.extractParamsPayload(payload);

        // Match to appropriate func
        if (this.receiveXChainDepositRequest.selector == _funcSig) {
            // Decode params
            (
                uint256 _pid,
                ,
                uint256 _weeksCommitted,
                uint256 _maxMarketMovement,
                bytes memory _originAccount,
                address _destAccount
            ) = abi.decode(
                    _paramsPayload,
                    (uint256, uint256, uint256, uint256, bytes, address)
                );

            // Call receiving function for cross chain deposits
            // Replace _valueUSDC to account for any slippage during bridging
            _receiveXChainDepositRequest(
                _pid,
                amountLD,
                _weeksCommitted,
                block.timestamp,
                _maxMarketMovement,
                _originAccount,
                _destAccount
            );
        } else if (this.receiveXChainRepatriationRequest.selector == _funcSig) {
            // Decode params from payload
            (
                uint256 _originChainId,
                uint256 _pid,
                uint256 _trancheId,
                bytes memory _originRecipient,
                uint256 _burnableZORRewards,
                uint256 _rewardsDue
            ) = abi.decode(
                    _paramsPayload,
                    (uint256, uint256, uint256, bytes, uint256, uint256)
                );
            // Forward request to repatriation function
            _receiveXChainRepatriationRequest(
                _originChainId,
                _pid,
                _trancheId,
                _originRecipient,
                _burnableZORRewards,
                _rewardsDue
            );
        } else if (this.receiveXChainDistributionRequest.selector == _funcSig) {
            // Decode params from payload
            (
                uint256 _remoteChainId,
                uint256 _amountUSDCBuyback,
                uint256 _amountUSDCRevShare,
                uint256 _accSlashedRewards,
                uint256 _maxMarketMovement
            ) = abi.decode(
                    _paramsPayload,
                    (uint256, uint256, uint256, uint256, uint256)
                );
            // Forward request to distribution function
            _receiveXChainDistributionRequest(
                _remoteChainId,
                _amountUSDCBuyback,
                _amountUSDCRevShare,
                _accSlashedRewards,
                _maxMarketMovement
            );
        } else {
            revert("Unrecognized func");
        }
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external override onlyRegXChainController(_srcChainId, _srcAddress) {
        // Determine function based on signature
        // Get func signature
        bytes4 _funcSig = bytes4(_payload);
        // Get params-only payload
        bytes memory _paramsPayload = this.extractParamsPayload(_payload);
        // Match to appropriate func
        if (this.receiveXChainWithdrawalRequest.selector == _funcSig) {
            // Decode params
            (
                uint256 _originChainId,
                bytes memory _originAccount,
                uint256 _pid,
                uint256 _trancheId,
                uint256 _maxMarketMovement
            ) = abi.decode(
                    _paramsPayload,
                    (uint256, bytes, uint256, uint256, uint256)
                );

            // Call receiving function for cross chain withdrawals
            // Replace _valueUSDC to account for any slippage during bridging
            _receiveXChainWithdrawalRequest(
                _originChainId,
                _originAccount,
                _pid,
                _trancheId,
                _maxMarketMovement
            );
        } else {
            revert("Unrecognized func");
        }
    }

    /// @notice Removes function signature from ABI encoded payload
    /// @param _payloadWithSig ABI encoded payload with function selector
    /// @return paramsPayload Payload with params only
    function extractParamsPayload(bytes calldata _payloadWithSig) public pure returns (bytes memory paramsPayload) {
        paramsPayload = _payloadWithSig[4:];
    }
}
