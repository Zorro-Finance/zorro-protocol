// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IStargateLPStaking {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;
}
