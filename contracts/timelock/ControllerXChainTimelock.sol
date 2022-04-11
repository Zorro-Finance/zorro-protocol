// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/governance/TimelockController.sol";

import "../interfaces/IVault.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IZorroControllerXChain.sol";

/// @title ControllerTimelock: A contract that owns all deployed Zorro controllers for safety
contract ControllerXChainTimelock is TimelockController {
    /* Constructors */
    constructor(
        uint256 _minDelay,
        address[] memory _proposers,
        address[] memory _executors
    ) TimelockController(_minDelay, _proposers, _executors) {}

    /* No timelock functions */

    function setControllerContract(
        address _controllerAddress, 
        uint256 _zorroChainId,
        bytes calldata _controller
    ) public onlyRole(EXECUTOR_ROLE) {
        IZorroControllerXChain(_controllerAddress).setControllerContract(_zorroChainId, _controller);
    }

    function setZorroChainToLZMap(address _controllerAddress, uint256 _zorroChainId, uint16 _lzChainId)
        public
        onlyRole(EXECUTOR_ROLE)
    {
        IZorroControllerXChain(_controllerAddress).setZorroChainToLZMap(_zorroChainId, _lzChainId);
    }

    function setStargateDestPoolIds(
        address _controllerAddress, 
        uint256 _zorroChainId,
        uint16 _stargatePoolId
    ) public onlyRole(EXECUTOR_ROLE) {
        IZorroControllerXChain(_controllerAddress).setStargateDestPoolIds(_zorroChainId, _stargatePoolId);
    }

    function setLayerZeroParams(
        address _controllerAddress, 
        address _stargateRouter,
        uint256 _stargateSwapPoolId,
        address _layerZeroEndpoint
    ) public onlyRole(EXECUTOR_ROLE) {
        IZorroControllerXChain(_controllerAddress).setLayerZeroParams(_stargateRouter, _stargateSwapPoolId, _layerZeroEndpoint);
    }
}
