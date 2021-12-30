// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.12 <0.9.0;

interface IAcryptosVault {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _shares) external;
}
