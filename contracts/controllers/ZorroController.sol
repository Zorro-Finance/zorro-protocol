// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/* Dependencies */
import "./_ZorroControllerBase.sol";

import "./_ZorroControllerPoolMgmt.sol";

import "./_ZorroControllerInvestment.sol";

import "./_ZorroControllerAnalytics.sol";

// TODO: In general, shouldn't these all be timelock contracts? 
// TODO: Make sure constructors and setters have all parameters as expected

/* Main Contract */
/// @title ZorroController: The main controller of the Zorro yield farming protocol. Used for cash flow operations (deposit/withdrawal), managing vaults, and rewards allocations, among other things.
contract ZorroController is ZorroControllerBase, ZorroControllerPoolMgmt, ZorroControllerInvestment, ZorroControllerAnalytics {
    /* Constructor */

    /// @notice Constructor
    /// @param _timelockOwner address of owner (should be a timelock)
    /// @param _lockUSDCController The address of the lock for USDC
    /// @param _homeChainZorroController The address of the home chain (BSC) Zorro controller contract
    /// @param _zorroLPPoolAddresses An array of: The address of the Zorro LP pool, token0 of the LP pool, and token1 of the pool
    /// @param _chainId The ID of the chain that this contract is being deployed on
    constructor(
        address _timelockOwner,
        address _publicPool,
        address[] memory _stableCoinAddresses,
        address _lockUSDCController,
        address _homeChainZorroController,
        address[] memory _zorroLPPoolAddresses,
        uint256 _chainId
    ) {
        // Assign owner as to timelock contract
        transferOwnership(_timelockOwner);
        // Set main state variables to initial state
        startBlock = block.timestamp;
        publicPool = _publicPool;
        defaultStablecoin = _stableCoinAddresses[0];
        syntheticStablecoin = _stableCoinAddresses[1];
        lockUSDCController = _lockUSDCController;
        require(_homeChainZorroController != address(0), "cannot be 0 addr");
        homeChainZorroController = _homeChainZorroController;
        zorroLPPool = _zorroLPPoolAddresses[0];
        zorroLPPoolToken0 = _zorroLPPoolAddresses[1];
        zorroLPPoolToken1 = _zorroLPPoolAddresses[2];
        chainId = _chainId;
    }
}