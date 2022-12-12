// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./_ZorroControllerXChainBase.sol";

import "../interfaces/Zorro/Controllers/IZorroController.sol";

import "../interfaces/Zorro/Controllers/IZorroControllerXChain.sol";

import "./actions/ZorroControllerXChainActions.sol";

contract ZorroControllerXChainDeposit is
    IZorroControllerXChainDeposit,
    ZorroControllerXChainBase
{
    /* Libraries */

    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* Sending */

    /// @notice Prepares and sends a cross chain deposit request. Takes care of necessary financial ops (transfer/locking USD)
    /// @dev Requires appropriate fee to be paid via msg.value (use checkXChainDepositFee() above)
    /// @param _zorroChainId The Zorro Chain ID (not the LayerZero one)
    /// @param _pid The pool ID on the remote chain
    /// @param _valueUSD The amount of  to deposit
    /// @param _weeksCommitted Number of weeks to commit to a vault
    /// @param _maxMarketMovement Acceptable degree of slippage on any transaction (e.g. 950 = 5%, 990 = 1% etc.)
    /// @param _destWallet A valid address on the remote chain that can claim ownership
    function sendXChainDepositRequest(
        uint256 _zorroChainId,
        uint256 _pid,
        uint256 _valueUSD,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        bytes memory _destWallet
    ) external payable nonReentrant {
        // Require funds to be submitted with this message
        require(msg.value > 0, "No fees submitted");

        // Transfer USD into this contract
        IERC20Upgradeable(defaultStablecoin).safeTransferFrom(
            msg.sender,
            address(this),
            _valueUSD
        );

        // Check balances
        uint256 _balUSD = IERC20Upgradeable(defaultStablecoin).balanceOf(
            address(this)
        );

        // Generate payload
        bytes memory _payload = ZorroControllerXChainActions(controllerActions)
            .encodeXChainDepositPayload(
                _pid,
                _balUSD,
                _weeksCommitted,
                _maxMarketMovement,
                msg.sender,
                _destWallet
            );

        // Get the destination contract address on the remote chain
        bytes memory _dstContract = controllerContractsMap[_zorroChainId];

        // Call stargate to initiate bridge
        _callStargateSwap(
            StargateSwapPayload({
                chainId: _zorroChainId,
                qty: _balUSD,
                dstContract: _dstContract,
                payload: _payload,
                maxMarketMovement: _maxMarketMovement
            })
        );
    }

    /* Receiving */

    /// @notice Dummy func to allow .selector call above and guarantee typesafety for abi calls.
    /// @dev Should never ever be actually called.
    function receiveXChainDepositRequest(
        uint256 _pid,
        uint256 _valueUSD,
        uint256 _weeksCommitted,
        uint256 _maxMarketMovement,
        bytes memory _originAccount,
        address _destAccount
    ) public {
        // Revert to make sure this function never gets called
        require(false, "illegal dummy func call");

        // But still include the function call here anyway to satisfy type safety requirements in case there is a change
        _receiveXChainDepositRequest(
            _pid,
            _valueUSD,
            _weeksCommitted,
            block.timestamp,
            _maxMarketMovement,
            _originAccount,
            _destAccount
        );
    }

    /// @notice Receives a cross chain deposit request from the contract layer of the XchainEndpoint contract
    /// @dev For params, see _depositFullService() function declaration above
    /// @param _pid The pool ID on the remote chain
    /// @param _valueUSD The amount of USD to deposit
    /// @param _weeksCommitted Number of weeks to commit to a vault
    /// @param _maxMarketMovement Acceptable degree of slippage on any transaction (e.g. 950 = 5%, 990 = 1% etc.)
    /// @param _originAccount The address on the origin chain to associate the deposit with (mandatory)
    /// @param _destAccount The address on the current chain to additionally associate the deposit with (allows on-chain withdrawals of the deposit) (if not provided, will truncate origin address to uint160 i.e. Solidity address type)
    function _receiveXChainDepositRequest(
        uint256 _pid,
        uint256 _valueUSD,
        uint256 _weeksCommitted,
        uint256 _vaultEnteredAt,
        uint256 _maxMarketMovement,
        bytes memory _originAccount,
        address _destAccount
    ) internal virtual {
        // Approve spending
        IERC20Upgradeable(defaultStablecoin).safeIncreaseAllowance(
            currentChainController,
            _valueUSD
        );

        // Call deposit function
        IZorroControllerInvestment(currentChainController)
            .depositFullServiceFromXChain(
                _pid,
                _destAccount,
                _originAccount,
                _valueUSD,
                _weeksCommitted,
                _vaultEnteredAt,
                _maxMarketMovement
            );
    }
}
