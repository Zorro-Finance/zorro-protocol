// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/* Dependencies */
import "./helpers/ERC20.sol";

import "./ZorroControllerBase.sol";

import "./ZorroControllerPoolMgmt.sol";

import "./ZorroControllerInvestment.sol";

import "./ZorroControllerAnalytics.sol";

/* Zorro ERC20 Token */
abstract contract ZorroToken is ERC20 {
    function mint(address _to, uint256 _amount) public virtual;
}

/* Main Contract */
/// @title ZorroController: The main controller of the Zorro yield farming protocol. Used for cash flow operations (deposit/withdrawal), managing vaults, and rewards allocations, among other things.
contract ZorroController is ZorroControllerBase, ZorroControllerPoolMgmt, ZorroControllerInvestment, ZorroControllerAnalytics {
    
}