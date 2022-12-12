// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "../interfaces/Zorro/Vaults/IVault.sol";

import "../interfaces/Zorro/Controllers/IZorroController.sol";

import "../interfaces/Zorro/Controllers/IZorroControllerXChain.sol";

/// @title ControllerTimelock: A contract that owns all deployed Zorro controllers for safety
contract ControllerTimelock is TimelockControllerUpgradeable {
    /* No timelock functions */

    /* ZorroController */

    // Base

    function updatePool(address _controllerAddress, uint256 _pid)
        public
        onlyRole(EXECUTOR_ROLE)
        returns (uint256)
    {
        return IZorroController(_controllerAddress).updatePool(_pid);
    }

    // PoolMgmt

    function add(
        address _controllerAddress, 
        uint256 _allocPoint,
        IERC20Upgradeable _want,
        bool _withUpdate,
        address _vault
    ) public onlyRole(EXECUTOR_ROLE) {
        IZorroController(_controllerAddress).add(
            _allocPoint,
            _want,
            _withUpdate,
            _vault
        );
    }

    function massUpdatePools(address _controllerAddress)
        public
        onlyRole(EXECUTOR_ROLE)
        returns (uint256)
    {
        return IZorroController(_controllerAddress).massUpdatePools();
    }

    /* ZorroControllerXChain */

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
