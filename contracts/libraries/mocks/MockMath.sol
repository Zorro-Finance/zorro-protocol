// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../Math.sol";

/// @title MockCustomMath: Mock contract for testing the CustomMath library
contract MockCustomMath {
    using CustomMath for uint256;

    function sqrt(uint256 x) public pure returns (uint256) {
        return x.sqrt();
    }
}