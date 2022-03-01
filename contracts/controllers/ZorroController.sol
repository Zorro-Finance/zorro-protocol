// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/* Dependencies */
import "../helpers/ERC20.sol";

import "./ZorroControllerBase.sol";

import "./ZorroControllerPoolMgmt.sol";

import "./ZorroControllerInvestment.sol";

import "./ZorroControllerAnalytics.sol";

/* Main Contract */
/// @title ZorroController: The main controller of the Zorro yield farming protocol. Used for cash flow operations (deposit/withdrawal), managing vaults, and rewards allocations, among other things.
contract ZorroController is ZorroControllerBase, ZorroControllerPoolMgmt, ZorroControllerInvestment, ZorroControllerAnalytics {
    /* Constructor */

    /// @notice Constructor
    /// @param _timelockOwner address of owner (should be a timelock)
    /// @param _zorroToken address of Zorro token
    /// @param _startBlock start block number. If current block is below this number, rewards won't be emitted. https://bscscan.com/block/countdown/13650292
    /// @param _publicPool address of the public pool to draw rewards from
    /// @param _BSCMarketTVLUSD total market TVL on the BSC chain in USD
    /// @param _ZorroTotalVaultTVLUSD total TVL locked into the Zorro protocol across all vaults
    /// @param _targetTVLCaptureBasisPoints how many basis points of the BSC total market TVL the protocol desires to capture (influences market aware emissions calcs)
    constructor(
        address _timelockOwner,
        address _zorroToken,
        uint256 _startBlock,
        address _publicPool,
        uint256 _BSCMarketTVLUSD,
        uint256 _ZorroTotalVaultTVLUSD,
        uint256 _targetTVLCaptureBasisPoints,
        address _defaultStablecoin
    ) {
        // Assign owner as to timelock contract
        transferOwnership(_timelockOwner);
        // Set main state variables to initial state
        ZORRO = _zorroToken;
        startBlock = _startBlock;
        publicPool = _publicPool;
        BSCMarketTVLUSD = _BSCMarketTVLUSD; 
        ZorroTotalVaultTVLUSD = _ZorroTotalVaultTVLUSD; 
        targetTVLCaptureBasisPoints = _targetTVLCaptureBasisPoints;
        defaultStablecoin = _defaultStablecoin;
    }
}