// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/governance/TimelockController.sol";

import "../interfaces/IVault.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IZorroController.sol";

/// @title ControllerTimelock: A contract that owns all deployed Zorro controllers for safety
contract ControllerTimelock is TimelockController {
    /* Constructors */
    constructor(
        uint256 _minDelay,
        address[] memory _proposers,
        address[] memory _executors
    ) TimelockController(_minDelay, _proposers, _executors) {}

    /* No timelock functions */

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
}
